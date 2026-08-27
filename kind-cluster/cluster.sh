#!/usr/bin/env bash
# Stands up or tears down the local kind cluster and Flux bootstrap via OpenTofu.
#
# Usage:
#   ./cluster.sh up       Create the cluster and apply the OpenTofu stack.
#   ./cluster.sh down     Destroy the OpenTofu stack and the cluster.
#   ./cluster.sh check    Wait for Flux and cert-manager to become ready and report status.
#   ./cluster.sh secrets  Apply GitHub tokens as Flux's git/OCI pull secrets.
#
# `secrets` reads GITHUB_USERNAME, GITHUB_TOKEN, and GHCR_TOKEN from the
# environment and creates two secrets in flux-system:
#   flux-git-auth  basic-auth secret for the GitRepository source, using
#                  GITHUB_TOKEN — a fine-grained PAT scoped to this repo
#                  with Contents: Read-only.
#   ghcr-pull      docker-registry secret for OCIRepository sources on
#                  ghcr.io, using GHCR_TOKEN — fine-grained PATs can't
#                  authenticate to GHCR, so this must be a classic PAT
#                  with the read:packages scope.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

usage() {
  echo "Usage: $0 {up|down|check|secrets}" >&2
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

secrets() {
  : "${GITHUB_USERNAME:?Set GITHUB_USERNAME to the account both tokens belong to}"
  : "${GITHUB_TOKEN:?Set GITHUB_TOKEN to a fine-grained PAT (Contents: Read-only) for git clone}"
  : "${GHCR_TOKEN:?Set GHCR_TOKEN to a classic PAT (read:packages scope) for GHCR pulls}"

  kubeconfig_env

  mise exec -- kubectl create secret generic flux-git-auth \
    --namespace flux-system \
    --from-literal=username="$GITHUB_USERNAME" \
    --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml | mise exec -- kubectl apply -f -

  mise exec -- kubectl create secret docker-registry ghcr-pull \
    --namespace flux-system \
    --docker-server=ghcr.io \
    --docker-username="$GITHUB_USERNAME" \
    --docker-password="$GHCR_TOKEN" \
    --dry-run=client -o yaml | mise exec -- kubectl apply -f -

  echo "Applied flux-git-auth and ghcr-pull secrets in flux-system."
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
  secrets)
    secrets
    ;;
  *)
    usage
    ;;
esac
