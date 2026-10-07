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
# Server-side apply avoids the client-side "metadata.annotations: Too long"
# failure: the ApplicationSet CRD alone exceeds the 256KB last-applied-config
# annotation limit that client-side apply tries to store.
kubectl apply -n argocd --server-side --force-conflicts -f "${ARGOCD_INSTALL_URL}"

wait_for_deployment argocd argocd-server 600s
wait_for_deployment argocd argocd-repo-server 600s
wait_for_statefulset argocd argocd-application-controller 600s

log "Configuring Argo CD server to run insecure internally (TLS is terminated at the ingress by cert-manager/Let's Encrypt)"
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge \
  -p '{"data":{"server.insecure":"true"}}'

kubectl rollout restart deployment/argocd-server -n argocd
wait_for_deployment argocd argocd-server 600s

log "Argo CD installation finished"
log "After bootstrap, the UI will be available on https://${ARGOCD_HOST}"
