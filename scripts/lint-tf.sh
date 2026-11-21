#!/usr/bin/env bash
# Terraform checks without AWS credentials (CONVENTIONS §1.7): fmt, forbidden resources,
# validate per stack (-backend=false) and tflint.
# init runs with its own TF_DATA_DIR under .cache/, so it never touches the real .terraform/
# (which points at the S3 backend), and with -lockfile=readonly so it can't change the lock files.
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"

echo "== terraform fmt" >&2
terraform fmt -check -recursive -diff terraform

echo "== forbidden resources" >&2
scripts/check-forbidden-resources.sh

for stack in bootstrap foundation cluster; do
  echo "== terraform validate: $stack" >&2
  export TF_DATA_DIR="$root/.cache/terraform/$stack"
  terraform -chdir="terraform/$stack" init -backend=false -input=false -lockfile=readonly >/dev/null
  terraform -chdir="terraform/$stack" validate
done
unset TF_DATA_DIR

echo "== tflint" >&2
tflint --init --config "$root/.tflint.hcl" >/dev/null
for dir in terraform/bootstrap terraform/foundation terraform/cluster terraform/modules/*/; do
  dir="${dir%/}"
  echo "-- $dir" >&2
  tflint --chdir="$dir" --config "$root/.tflint.hcl"
done
