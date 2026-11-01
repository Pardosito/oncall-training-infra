#!/usr/bin/env bash
# Step 1 of `make cluster-down` (ARCHITECTURE §13.3): delete the Ingress and wait until the
# controller has removed the ALB and its security groups. Otherwise they block the VPC destroy
# and the ALB keeps billing. Safe to run when the cluster is already gone.
set -euo pipefail

REGION="us-east-1"
CLUSTER_NAME="${CLUSTER_NAME:-oncall-training}"
ALB_NAME="oncall-training-api"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"

if aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null
  echo "Deleting Ingress app/backend-api (removes the ALB)..." >&2
  kubectl delete ingress -n app backend-api --ignore-not-found --wait=true --timeout=300s || \
    echo "warning: Ingress delete didn't finish; still waiting for the ALB below" >&2
else
  echo "Cluster $CLUSTER_NAME not found; only checking for a leftover ALB." >&2
fi

vpc_id="$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Name,Values=$CLUSTER_NAME" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while :; do
  alb="$(aws elbv2 describe-load-balancers --region "$REGION" --names "$ALB_NAME" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)"
  sgs=""
  if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
    sgs="$(aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=vpc-id,Values=$vpc_id" "Name=tag-key,Values=elbv2.k8s.aws/cluster" \
      --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || true)"
  fi
  if { [ -z "$alb" ] || [ "$alb" = "None" ]; } && [ -z "$sgs" ]; then
    echo "ALB and controller security groups are gone." >&2
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "error: ALB ($alb) or controller SGs ($sgs) still exist after ${TIMEOUT_SECONDS}s." >&2
    echo "Delete them in the console (EC2 → Load Balancers / Security Groups), then re-run make cluster-down." >&2
    exit 1
  fi
  echo "Waiting for the ALB/security groups to be deleted..." >&2
  sleep 10
done
