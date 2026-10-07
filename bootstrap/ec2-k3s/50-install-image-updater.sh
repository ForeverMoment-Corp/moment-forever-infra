#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
load_env
compute_hosts
require_env DOCKERHUB_USERNAME DOCKERHUB_TOKEN

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

log "Installing Argo CD Image Updater"
kubectl apply -n argocd --server-side --force-conflicts -f "${ARGOCD_IMAGE_UPDATER_INSTALL_URL}"

# Upstream renamed the Deployment from "argocd-image-updater" to
# "argocd-image-updater-controller"; wait on the current name.
wait_for_deployment argocd argocd-image-updater-controller 600s

log "Creating Docker Hub registry secret for Image Updater"
kubectl create secret docker-registry dockerhub-secret \
  --namespace argocd \
  --docker-server https://registry-1.docker.io \
  --docker-username "${DOCKERHUB_USERNAME}" \
  --docker-password "${DOCKERHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Configuring Image Updater registry access"
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  log.level: info
  registries.conf: |
    registries:
    - name: Docker Hub
      prefix: docker.io
      api_url: https://registry-1.docker.io
      defaultns: library
      default: true
      credentials: pullsecret:argocd/dockerhub-secret
EOF

kubectl rollout restart deployment/argocd-image-updater-controller -n argocd
wait_for_deployment argocd argocd-image-updater-controller 600s

log "Argo CD Image Updater installation finished"
log "It will reuse the Argo CD repository credentials for Git write-back because your Application manifests use write-back method 'git'."
