#!/usr/bin/env bash
# Builds the aws overlay and applies it to the current kubectl context (EKS).
# Called by `make cluster-up` and `make deploy`, which ask for confirmation first.
set -euo pipefail

cd "$(dirname "$0")/.."
OVERLAY="k8s/overlays/aws"
CLUSTER_NAME="${CLUSTER_NAME:-oncall-training}"

for f in config.env cluster.env; do
  [ -f "$OVERLAY/$f" ] || { echo "error: $OVERLAY/$f missing; run scripts/render-config.sh" >&2; exit 1; }
done

context="$(kubectl config current-context)"
case "$context" in
  *":cluster/$CLUSTER_NAME") ;;
  *) echo "error: kubectl context is '$context', not the EKS cluster $CLUSTER_NAME" >&2; exit 1 ;;
esac

grep -E '^[A-Z_]+_TAG=' "$OVERLAY/images.env" | sed 's/^/  /' >&2
echo "Applying $OVERLAY to $context..." >&2
kustomize build "$OVERLAY" | kubectl apply -f -
