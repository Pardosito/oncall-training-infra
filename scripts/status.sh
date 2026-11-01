#!/usr/bin/env bash
# `make status`: what's running on EKS and what it costs (ARCHITECTURE §13.5).
set -euo pipefail

cd "$(dirname "$0")/.."
REGION="us-east-1"
CLUSTER_NAME="${CLUSTER_NAME:-oncall-training}"

if ! aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "Cluster $CLUSTER_NAME is down (not billing). Foundation stays up."
  exit 0
fi
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null

echo "== Nodes"; kubectl get nodes -o wide
for ns in app injector mock; do
  echo; echo "== Pods in $ns"; kubectl get pods -n "$ns" -o wide 2>/dev/null || true
done
echo; echo "== Images (k8s/overlays/aws/images.env)"; grep -E '^[A-Z_]+_TAG=' k8s/overlays/aws/images.env
alb="$(kubectl get ingress -n app backend-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
echo; echo "== ALB: ${alb:-not provisioned yet}"
[ -n "$alb" ] && echo "   API_PROXY_TARGET=http://$alb"
echo
echo "⚠  The cluster bills about \$0.25/h (≈ \$6/day). Run 'make cluster-down' before you stop working."
