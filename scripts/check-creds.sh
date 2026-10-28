#!/usr/bin/env bash
# Fails fast when the Learner Lab credentials are missing or expired.
# Every AWS-touching make target depends on `check-creds`, and workflows run it
# before anything else. Uses the default credential chain (env vars in CI,
# ~/.aws/credentials locally).
set -euo pipefail

REGION="us-east-1"

command -v aws >/dev/null || { echo "error: aws CLI not found; run mise install" >&2; exit 1; }

if ! account="$(aws sts get-caller-identity --region "$REGION" --query Account --output text 2>/dev/null)"; then
  echo "error: Lab credentials expired — run make creds" >&2
  exit 1
fi

echo "Lab credentials OK (account $account)" >&2
