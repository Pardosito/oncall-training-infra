#!/usr/bin/env bash
# `terraform init` for the foundation or cluster stack with its S3 backend.
# - Refuses a backend.hcl written for another lab account (run make bootstrap first).
# - -reconfigure: backend.hcl changes when the lab account changes, and the old account's
#   state must never be migrated into the new bucket.
# - Quiet on success, prints terraform's output on failure.
# Usage: scripts/tf-init.sh foundation|cluster
set -euo pipefail

stack="${1:?usage: tf-init.sh foundation|cluster}"
cd "$(dirname "$0")/.."
dir="terraform/$stack"
REGION="us-east-1"

[ -f "$dir/backend.hcl" ] || {
  echo "error: $dir/backend.hcl missing; run make backend-config (or make bootstrap on a new lab account)" >&2
  exit 1
}

account="$(aws sts get-caller-identity --region "$REGION" --query Account --output text)"
bucket="$(sed -nE 's/^bucket *= *"([^"]+)".*/\1/p' "$dir/backend.hcl")"
expected="oncall-training-tfstate-$account"
if [ "$bucket" != "$expected" ]; then
  echo "error: $dir/backend.hcl points at $bucket, but the credentials are for account $account." >&2
  echo "New lab account? Run make bootstrap (it rewrites backend.hcl), then make foundation-apply." >&2
  exit 1
fi

if ! out="$(terraform -chdir="$dir" init -input=false -reconfigure -backend-config=backend.hcl 2>&1)"; then
  printf '%s\n' "$out" >&2
  echo "error: terraform init failed for $stack" >&2
  exit 1
fi
