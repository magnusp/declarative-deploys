#!/usr/bin/env bash
# Stands up or tears down the local kind cluster and Flux bootstrap via OpenTofu.
#
# Usage:
#   ./cluster.sh up       Create the cluster and apply the OpenTofu stack.
#   ./cluster.sh down     Destroy the OpenTofu stack and the cluster.
#   ./cluster.sh check    Wait for Flux and cert-manager to become ready and report status.
#
# The repository is public, and the chart OCIRepository sources under
# clusters/kind/ assume their GHCR packages are also public, so Flux needs
# no credentials for either. If a source is added that isn't public, apply
# its pull secret manually with `kubectl create secret ... -n flux-system`
# and reference it via that source's secretRef.
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

  echo "Waiting for flux-system pods..."
  mise exec -- kubectl wait --for=condition=Ready pods --all -n flux-system --timeout=180s

  echo "Waiting for FluxInstance to become Ready..."
  mise exec -- kubectl wait --for=condition=Ready fluxinstance/flux -n flux-system --timeout=180s

  echo "Waiting for cert-manager HelmRelease to become Ready..."
  mise exec -- kubectl wait --for=condition=Ready helmrelease/cert-manager -n flux-system --timeout=180s

  echo "Waiting for cert-manager pods..."
  mise exec -- kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=180s

  echo
  echo "--- flux-system pods ---"
  mise exec -- kubectl get pods -n flux-system
  echo
  echo "--- cert-manager pods ---"
  mise exec -- kubectl get pods -n cert-manager
  echo
  echo "Cluster and Flux bootstrap are healthy."
}

[ $# -eq 1 ] || usage

case "$1" in
  up)
    mise install
    mise exec -- tofu init
    mise exec -- tofu apply -auto-approve
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
