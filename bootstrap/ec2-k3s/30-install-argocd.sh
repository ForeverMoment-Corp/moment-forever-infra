#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
load_env
compute_hosts

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
command_exists kubectl || die "kubectl not found. Run 10-install-k3s.sh first."

log "Installing Argo CD into namespace argocd"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f "${ARGOCD_INSTALL_URL}"

wait_for_deployment argocd argocd-server 600s
wait_for_deployment argocd argocd-repo-server 600s
wait_for_statefulset argocd argocd-application-controller 600s

log "Configuring Argo CD server to run insecure behind HTTP ingress"
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge \
  -p '{"data":{"server.insecure":"true"}}'

kubectl rollout restart deployment/argocd-server -n argocd
wait_for_deployment argocd argocd-server 600s

log "Argo CD installation finished"
log "After bootstrap, the UI will be available on http://${ARGOCD_HOST}"
