#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
load_env
require_ubuntu_2204
compute_hosts

if systemctl is-active --quiet k3s; then
  log "k3s is already installed and running; skipping install"
else
  log "Installing k3s server with Traefik disabled"
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_CHANNEL="${K3S_CHANNEL}" \
    INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 644 --tls-san ${PUBLIC_IP}" \
    sh -
fi

log "Waiting for k3s service"
systemctl enable k3s >/dev/null 2>&1 || true
systemctl is-active --quiet k3s || die "k3s service is not active"

configure_kubeconfig_for_login_user

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes -o wide

log "k3s installation finished"
