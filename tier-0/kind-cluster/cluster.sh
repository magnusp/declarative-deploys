#!/usr/bin/env bash
# Stands up or tears down the local kind cluster via OpenTofu, and applies the
# raw manifests in ../manifests/ directly with kubectl. There is no
# reconciler here — re-running `up` (or `kubectl apply`) is the only way
# changes to ../manifests/ reach the cluster.
#
# Usage:
#   ./cluster.sh up       Create the cluster and kubectl apply ../manifests/.
#   ./cluster.sh down     Destroy the OpenTofu stack and the cluster.
#   ./cluster.sh check    Wait for node readiness and print pod status.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

usage() {
  echo "Usage: $0 {up|down|check}" >&2
  exit 1
}

kubeconfig_env() {
  KUBECONFIG=$(mktemp)
  export KUBECONFIG
  mise exec -- tofu output -raw kubeconfig > "$KUBECONFIG"
}

check() {
  kubeconfig_env

  echo "Waiting for cluster nodes..."
  mise exec -- kubectl wait --for=condition=Ready nodes --all --timeout=180s

  echo
  echo "--- apps namespace pods ---"
  mise exec -- kubectl get pods -n apps 2>/dev/null || echo "(namespace 'apps' not applied yet)"
  echo
  echo "Cluster is healthy."
}

[ $# -eq 1 ] || usage

case "$1" in
  up)
    mise install
    mise exec -- tofu init
    mise exec -- tofu apply -auto-approve
    kubeconfig_env
    echo "Applying ../manifests/ by hand..."
    mise exec -- kubectl apply -f ../manifests/
    check
    ;;
  down)
    mise exec -- tofu destroy -auto-approve
    ;;
  check)
    check
    ;;
  *)
    usage
    ;;
esac
