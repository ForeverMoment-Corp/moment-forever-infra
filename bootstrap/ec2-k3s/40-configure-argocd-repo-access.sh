#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
load_env
compute_hosts
require_env GITHUB_USERNAME GITHUB_TOKEN INFRA_REPO_URL

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log "Creating or updating Argo CD repository credentials for ${INFRA_REPO_URL}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: moment-forever-infra-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${INFRA_REPO_URL}
  username: ${GITHUB_USERNAME}
  password: ${GITHUB_TOKEN}
EOF

log "Argo CD repository credentials configured"
