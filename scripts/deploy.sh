#!/usr/bin/env bash
# `make deploy` (ARCHITECTURE §13.4): checks each given tag exists in ECR, writes it to
# images.env, re-applies the aws overlay and waits for the rollouts.
# Usage: scripts/deploy.sh [BACKEND_TAG=<sha>] [INJECTOR_TAG=<sha>] [MOCK_TAG=<sha>]
set -euo pipefail

cd "$(dirname "$0")/.."
REGION="us-east-1"
IMAGES_ENV="k8s/overlays/aws/images.env"

declare -a rollouts=()
changed=0
for arg in "$@"; do
  key="${arg%%=*}"
  tag="${arg#*=}"
  [ -n "$tag" ] || continue
  case "$key" in
    BACKEND_TAG)  repo="oncall-training/backend";     rollouts+=("app/backend-api" "app/backend-worker") ;;
    INJECTOR_TAG) repo="oncall-training/injector";    rollouts+=("injector/injector") ;;
    MOCK_TAG)     repo="oncall-training/mock-system"; rollouts+=("mock/gateway" "mock/orders" "mock/worker-svc") ;;
    *) echo "error: unknown argument $arg" >&2; exit 1 ;;
  esac
  [[ "$tag" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: $key=$tag is not a git SHA" >&2; exit 1; }
  if ! aws ecr describe-images --region "$REGION" --repository-name "$repo" --image-ids "imageTag=$tag" >/dev/null 2>&1; then
    echo "error: $repo:$tag is not in ECR" >&2
    exit 1
  fi
  sed -i.bak "s/^$key=.*/$key=$tag/" "$IMAGES_ENV" && rm -f "$IMAGES_ENV.bak"
  echo "$key=$tag" >&2
  changed=1
done

[ "$changed" = 1 ] || { echo "error: pass at least one of BACKEND_TAG, INJECTOR_TAG, MOCK_TAG" >&2; exit 1; }

scripts/k8s-apply.sh

for r in "${rollouts[@]}"; do
  ns="${r%%/*}"
  name="${r#*/}"
  replicas="$(kubectl get deploy -n "$ns" "$name" -o jsonpath='{.spec.replicas}')"
  if [ "$replicas" = "0" ]; then
    echo "$r has 0 replicas (see the replicas block in the aws overlay); not waiting" >&2
    continue
  fi
  kubectl rollout status -n "$ns" "deploy/$name" --timeout=180s
done

echo "Deployed. Commit $IMAGES_ENV so the running versions are in git." >&2
