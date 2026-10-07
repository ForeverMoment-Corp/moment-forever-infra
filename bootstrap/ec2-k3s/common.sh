#!/usr/bin/env bash
set -Eeuo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BOOTSTRAP_DIR/../.." && pwd)"
ENV_FILE="${BOOTSTRAP_ENV_FILE:-$BOOTSTRAP_DIR/.env}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "Re-running $0 with sudo"
    exec sudo -E bash "$0" "$@"
  fi
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi

  : "${INFRA_REPO_URL:=https://github.com/ForeverMoment-Corp/moment-forever-infra.git}"
  : "${INFRA_REPO_BRANCH:=main}"
  : "${K3S_CHANNEL:=stable}"
  : "${INGRESS_NGINX_MANIFEST_URL:=https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.3/deploy/static/provider/cloud/deploy.yaml}"
  : "${ARGOCD_INSTALL_URL:=https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
  : "${ARGOCD_IMAGE_UPDATER_INSTALL_URL:=https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/config/install.yaml}"
  : "${CERT_MANAGER_INSTALL_URL:=https://github.com/cert-manager/cert-manager/releases/download/v1.21.2/cert-manager.yaml}"
  : "${PUBLIC_IP:=}"
  : "${APP_HOST:=}"
  : "${ARGOCD_HOST:=}"
  : "${DASHBOARD_HOST:=}"
}

require_env() {
  local var_name
  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      die "Required variable '$var_name' is missing. Fill $ENV_FILE first."
    fi
  done
}

# Ubuntu LTS versions this bootstrap has been validated against. Add a new
# entry here (and re-test the scripts) before moving the fleet to a newer
# Ubuntu LTS release.
SUPPORTED_UBUNTU_VERSIONS=("22.04" "24.04")

require_ubuntu_2204() {
  if [[ ! -f /etc/os-release ]]; then
    die "/etc/os-release not found. This bootstrap targets Ubuntu LTS (${SUPPORTED_UBUNTU_VERSIONS[*]})."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  local version
  for version in "${SUPPORTED_UBUNTU_VERSIONS[@]}"; do
    if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "$version" ]]; then
      return 0
    fi
  done

  die "Unsupported OS '${PRETTY_NAME:-unknown}'. Use one of Ubuntu ${SUPPORTED_UBUNTU_VERSIONS[*]} LTS for this bootstrap."
}

resolve_public_ip() {
  if [[ -n "${PUBLIC_IP}" ]]; then
    return
  fi

  local token
  token="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)"

  if [[ -n "$token" ]]; then
    PUBLIC_IP="$(curl -fsS -H "X-aws-ec2-metadata-token: $token" \
      http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
  fi

  if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]' || true)"
  fi

  if [[ -z "${PUBLIC_IP}" ]]; then
    die "Unable to determine EC2 public IP automatically. Set PUBLIC_IP in $ENV_FILE."
  fi
}

compute_hosts() {
  resolve_public_ip
  if [[ -z "${APP_HOST}" ]]; then
    APP_HOST="api.${PUBLIC_IP}.nip.io"
  fi
  if [[ -z "${ARGOCD_HOST}" ]]; then
    ARGOCD_HOST="argocd.${PUBLIC_IP}.nip.io"
  fi
  if [[ -z "${DASHBOARD_HOST}" ]]; then
    DASHBOARD_HOST="dashboard.${PUBLIC_IP}.nip.io"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

wait_for_deployment() {
  local namespace="$1"
  local name="$2"
  local timeout="${3:-600s}"
  kubectl rollout status "deployment/${name}" -n "$namespace" --timeout="$timeout"
}

wait_for_statefulset() {
  local namespace="$1"
  local name="$2"
  local timeout="${3:-600s}"
  kubectl rollout status "statefulset/${name}" -n "$namespace" --timeout="$timeout"
}

wait_for_load_balancer_ip() {
  local namespace="$1"
  local service="$2"
  local timeout_seconds="${3:-300}"
  local deadline shell_now current
  deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    current="$(kubectl get svc "$service" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    if [[ -n "$current" ]]; then
      log "Service ${namespace}/${service} is exposed via: $current"
      return 0
    fi
    sleep 5
  done

  warn "Timed out waiting for external address on ${namespace}/${service}. This is common on small single-node labs; continue and test from the EC2 public IP."
}

configure_kubeconfig_for_login_user() {
  local login_user login_home
  login_user="${SUDO_USER:-ubuntu}"
  if ! getent passwd "$login_user" >/dev/null 2>&1; then
    warn "User '$login_user' does not exist; skipping kubeconfig copy."
    return
  fi

  login_home="$(getent passwd "$login_user" | cut -d: -f6)"
  mkdir -p "$login_home/.kube"
  cp /etc/rancher/k3s/k3s.yaml "$login_home/.kube/config"
  chown -R "$login_user:$login_user" "$login_home/.kube"
  chmod 600 "$login_home/.kube/config"
}

warn_if_low_resources() {
  local total_mem_mb available_disk_gb
  total_mem_mb="$(free -m | awk '/^Mem:/ {print $2}')"
  available_disk_gb="$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')"

  if [[ "${total_mem_mb}" -lt 3500 ]]; then
    warn "This VM has ${total_mem_mb}MB RAM. k3s and the GitOps control plane will install, but all Moment Forever workloads may not stay healthy together on a free-tier sized machine."
  fi

  if [[ "${available_disk_gb}" -lt 15 ]]; then
    warn "Only ${available_disk_gb}GB disk is currently free. Container images, logs, and databases may exhaust storage quickly."
  fi
}

ensure_repo_branch_synced() {
  local local_head remote_head
  cd "$REPO_ROOT"
  git fetch origin "$INFRA_REPO_BRANCH" --quiet
  local_head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse "origin/${INFRA_REPO_BRANCH}")"
  if [[ "$local_head" != "$remote_head" ]]; then
    die "Local checkout is not the same as origin/${INFRA_REPO_BRANCH}. Commit and push infra repo changes before bootstrapping Argo CD."
  fi
}

validate_manifest_inputs() {
  local manifest
  grep -q -- "- \"${INFRA_REPO_URL}\"" "$REPO_ROOT/argocd/app-project.yaml" \
    || die "argocd/app-project.yaml sourceRepos does not include ${INFRA_REPO_URL}"
  for manifest in "$REPO_ROOT/argocd/root-application.yaml" "$REPO_ROOT"/argocd/applications/*.yaml; do
    # repoURL is written with or without surrounding quotes across manifests
    # (e.g. `repoURL: https://...` vs `repoURL: "https://..."`), so match the
    # URL itself rather than anchoring on an exact quoting style.
    grep -q -- "${INFRA_REPO_URL}" "$manifest" \
      || die "${manifest#$REPO_ROOT/} does not point to ${INFRA_REPO_URL}"
    grep -q "targetRevision: ${INFRA_REPO_BRANCH}" "$manifest" \
      || die "${manifest#$REPO_ROOT/} targetRevision is not ${INFRA_REPO_BRANCH}"
  done
  grep -q "host: ${APP_HOST}" "$REPO_ROOT/clusters/dev/ingress/ingress.yaml" \
    || die "clusters/dev/ingress/ingress.yaml is not configured for ${APP_HOST}"
  grep -q "host: ${ARGOCD_HOST}" "$REPO_ROOT/clusters/dev/argocd/ingress.yaml" \
    || die "clusters/dev/argocd/ingress.yaml is not configured for ${ARGOCD_HOST}"
  grep -q "host: ${DASHBOARD_HOST}" "$REPO_ROOT/clusters/dev/dashboard/ingress.yaml" \
    || die "clusters/dev/dashboard/ingress.yaml is not configured for ${DASHBOARD_HOST}"
}
