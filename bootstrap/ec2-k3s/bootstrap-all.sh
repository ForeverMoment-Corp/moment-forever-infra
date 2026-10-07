#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

bash "$SCRIPT_DIR/00-prepare-host.sh" "$@"
bash "$SCRIPT_DIR/10-install-k3s.sh" "$@"
bash "$SCRIPT_DIR/20-install-nginx-ingress.sh" "$@"
bash "$SCRIPT_DIR/25-install-cert-manager.sh" "$@"
bash "$SCRIPT_DIR/30-install-argocd.sh" "$@"
bash "$SCRIPT_DIR/40-configure-argocd-repo-access.sh" "$@"
bash "$SCRIPT_DIR/50-install-image-updater.sh" "$@"
bash "$SCRIPT_DIR/60-bootstrap-moment-forever.sh" "$@"
