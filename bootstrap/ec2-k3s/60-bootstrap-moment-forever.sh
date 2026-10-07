#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
load_env
compute_hosts

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

ensure_repo_branch_synced
validate_manifest_inputs

log "Applying Argo CD AppProject and root application from local checkout"
kubectl apply -f "$REPO_ROOT/argocd/app-project.yaml"
kubectl apply -f "$REPO_ROOT/argocd/root-application.yaml"

log "Waiting for root application to exist"
for _ in $(seq 1 60); do
  if kubectl get application moment-forever-root -n argocd >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
kubectl get application moment-forever-root -n argocd >/dev/null 2>&1 || die "Argo CD root application was not created"

log "Waiting for child applications to appear"
for app_name in \
  ingress \
  argocd-ui \
  dashboard \
  moment-forever-shared-infra-dev \
  moment-forever-platform-dev \
  moment-forever-booking-dev \
  moment-forever-payment-dev \
  moment-forever-gateway-dev
do
  for _ in $(seq 1 60); do
    if kubectl get application "$app_name" -n argocd >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
  kubectl get application "$app_name" -n argocd >/dev/null 2>&1 || die "Expected child application '$app_name' was not created"
done

log "Bootstrap finished. Argo CD is now managing Moment Forever from Git."
log "App URL: http://${APP_HOST}"
log "Argo CD URL: http://${ARGOCD_HOST}"
log "Kubernetes Dashboard URL: http://${DASHBOARD_HOST}"
log "Get a Dashboard login token with:"
log "  kubectl -n kubernetes-dashboard create token admin-user"
log "Watch sync state with: kubectl get applications -n argocd"
