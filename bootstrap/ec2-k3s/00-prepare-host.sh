#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
load_env
require_ubuntu_2204
warn_if_low_resources

log "Updating APT package index"
apt-get update -y

log "Installing host prerequisites"
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gettext-base \
  git \
  gnupg \
  jq \
  lsb-release \
  software-properties-common

log "Host preparation finished"
log "Reminder: EC2 security group should allow inbound 22, 80, and 443 to reach SSH and ingress."
