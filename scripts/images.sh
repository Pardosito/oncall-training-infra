#!/usr/bin/env bash
# Builds and pushes the injector and mock-system images to ECR (ARCHITECTURE §13.4).
# Tag = short git SHA of a clean tree (ECR tags are immutable). linux/amd64: EKS nodes are x86_64.
set -euo pipefail

cd "$(dirname "$0")/.."
REGION="us-east-1"

if [ -n "$(git status --porcelain -- services package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json)" ]; then
  echo "error: uncommitted changes under services/ (or workspace files); commit first so the tag matches the code" >&2
  exit 1
fi
tag="$(git rev-parse --short=12 HEAD)"

urls="$(terraform -chdir=terraform/foundation output -json ecr_repository_urls)"
registry="$(jq -r '.["mock-system"]' <<<"$urls")"
registry="${registry%%/*}"

echo "Logging in to $registry..." >&2
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$registry" >/dev/null

for svc in mock-system injector; do
  repo="oncall-training/$svc"
  image="$registry/$repo:$tag"
  if aws ecr describe-images --region "$REGION" --repository-name "$repo" --image-ids "imageTag=$tag" >/dev/null 2>&1; then
    echo "$image already in ECR; skipping" >&2
    continue
  fi
  echo "Building and pushing $image (linux/amd64)..." >&2
  docker buildx build --platform linux/amd64 -f "services/$svc/Dockerfile" -t "$image" --push .
done

echo
echo "Pushed. Roll out with:"
echo "  make deploy MOCK_TAG=$tag INJECTOR_TAG=$tag"
