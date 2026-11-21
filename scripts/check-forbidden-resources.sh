#!/usr/bin/env bash
# Fails if the Terraform code declares a resource type the Learner Lab forbids (CONVENTIONS §1.4):
#   - any IAM resource (aws_iam_* / awscc_iam_*), except service-linked roles
#   - Pod Identity associations
#   - aws_s3_bucket: use awscc_s3_bucket (D-24); aws_s3_bucket_policy and friends are fine
# Data sources (data "aws_iam_role" "lab") are allowed.
set -euo pipefail

cd "$(dirname "$0")/.."

forbidden='^[[:space:]]*resource[[:space:]]+"((aws|awscc)_iam_[a-z0-9_]+|(aws|awscc)_eks_pod_identity_association|aws_s3_bucket)"'
allowed='"aws_iam_service_linked_role"'

hits="$(grep -rnE --include='*.tf' --exclude-dir=.terraform "$forbidden" terraform | grep -v "$allowed" || true)"

if [ -n "$hits" ]; then
  echo "error: forbidden resource types (CONVENTIONS §1.4, D-24):" >&2
  echo "$hits" >&2
  echo "Use data \"aws_iam_role\" \"lab\" (LabRole) for roles and awscc_s3_bucket for buckets." >&2
  exit 1
fi
echo "forbidden resources: none"
