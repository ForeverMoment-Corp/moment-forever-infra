#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

ensure_root "$@"
load_env
require_env LETSENCRYPT_EMAIL

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
command_exists kubectl || die "kubectl not found. Run 10-install-k3s.sh first."

log "Installing cert-manager"
kubectl apply --server-side --force-conflicts -f "${CERT_MANAGER_INSTALL_URL}"

wait_for_deployment cert-manager cert-manager 600s
wait_for_deployment cert-manager cert-manager-webhook 600s
wait_for_deployment cert-manager cert-manager-cainjector 600s

# cert-manager's webhook pod takes a few seconds to be reachable even after
# the Deployment reports Available, so creating a ClusterIssuer right away
# can fail with "connection refused" / "no endpoints available". Retry.
CLUSTER_ISSUERS_MANIFEST="$(cat <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
EOF
)"

log "Configuring Let's Encrypt ClusterIssuers (letsencrypt-staging, letsencrypt-prod)"
applied=false
for attempt in $(seq 1 24); do
  if echo "${CLUSTER_ISSUERS_MANIFEST}" | kubectl apply -f -; then
    applied=true
    break
  fi
  warn "cert-manager webhook not ready yet (attempt ${attempt}/24); retrying in 5s"
  sleep 5
done

if [[ "${applied}" != "true" ]]; then
  die "Could not create ClusterIssuers; cert-manager webhook never became ready. Check: kubectl get pods -n cert-manager"
fi

log "cert-manager installation finished"
log "Ingress resources request real HTTPS certs with annotation: cert-manager.io/cluster-issuer: letsencrypt-prod"
log "Use letsencrypt-staging while iterating/testing to avoid Let's Encrypt production rate limits (5 duplicate certs/week per host)."
