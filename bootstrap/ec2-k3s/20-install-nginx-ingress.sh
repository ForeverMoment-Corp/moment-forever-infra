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

log "Installing NGINX Ingress Controller"
kubectl apply -f "${INGRESS_NGINX_MANIFEST_URL}"

wait_for_deployment ingress-nginx ingress-nginx-controller 600s
wait_for_load_balancer_ip ingress-nginx ingress-nginx-controller 300

log "NGINX Ingress Controller installation finished"
