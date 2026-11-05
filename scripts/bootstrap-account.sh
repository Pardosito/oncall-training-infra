#!/usr/bin/env bash
# Runs before `make bootstrap`. The bootstrap state is local (D-02), so after a lab account
# change it still describes the old account's state bucket, and the plan fails with
# "Unexpected Identity Change". If the state belongs to another account, move it (and any
# saved plan) to terraform/bootstrap/archive/<old account>/ so bootstrap starts clean.
set -euo pipefail

cd "$(dirname "$0")/../terraform/bootstrap"
REGION="us-east-1"

current="$(aws sts get-caller-identity --region "$REGION" --query Account --output text)"

[ -f terraform.tfstate ] || { echo "No local bootstrap state; bootstrapping account $current." >&2; exit 0; }

# account_id output first; fall back to the account suffix of the state bucket name.
recorded="$(jq -r '.outputs.account_id.value // empty' terraform.tfstate)"
if [ -z "$recorded" ]; then
  bucket="$(jq -r '.outputs.state_bucket.value // empty' terraform.tfstate)"
  recorded="${bucket##*-}"
fi

if [ -z "$recorded" ] || [ "$recorded" = "$current" ]; then
  echo "Bootstrap state matches account $current." >&2
  exit 0
fi

archive="archive/$recorded"
echo "Bootstrap state is for account $recorded, but the credentials are for $current." >&2
echo "Moving the old state to terraform/bootstrap/$archive/ (gitignored, kept in case that account comes back)." >&2
mkdir -p "$archive"
for f in terraform.tfstate terraform.tfstate.*backup bootstrap.tfplan; do
  [ -e "$f" ] && mv "$f" "$archive/"
done
exit 0
