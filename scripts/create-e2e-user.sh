#!/usr/bin/env bash
# Creates (or resets) a confirmed Cognito user for demos and the e2e test (INF-034, D-22).
# The password comes from the environment so it never lands in git or the Terraform state.
#
#   E2E_USERNAME=demo E2E_PASSWORD='...' scripts/create-e2e-user.sh
#
# Needs the foundation stack applied (reads the cognito_user_pool_id output).
set -euo pipefail

cd "$(dirname "$0")/.."
REGION="us-east-1"
: "${E2E_USERNAME:=e2e}"
: "${E2E_PASSWORD:?set E2E_PASSWORD (8+ chars, upper, lower and a number)}"
E2E_EMAIL="${E2E_EMAIL:-$E2E_USERNAME@example.com}"

pool="$(terraform -chdir=terraform/foundation output -raw cognito_user_pool_id)"

if aws cognito-idp admin-get-user --region "$REGION" --user-pool-id "$pool" \
  --username "$E2E_USERNAME" >/dev/null 2>&1; then
  echo "User $E2E_USERNAME exists; resetting its password." >&2
else
  aws cognito-idp admin-create-user --region "$REGION" --user-pool-id "$pool" \
    --username "$E2E_USERNAME" --message-action SUPPRESS \
    --user-attributes Name=email,Value="$E2E_EMAIL" Name=email_verified,Value=true >/dev/null
  echo "Created user $E2E_USERNAME." >&2
fi

aws cognito-idp admin-set-user-password --region "$REGION" --user-pool-id "$pool" \
  --username "$E2E_USERNAME" --password "$E2E_PASSWORD" --permanent
echo "User $E2E_USERNAME is confirmed and can sign in." >&2
