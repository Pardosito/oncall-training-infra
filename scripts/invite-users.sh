#!/usr/bin/env bash
# Invites Cognito users from a file (D-32; users can also sign up themselves, D-35). One user per line:
#   <username> <email>
# Blank lines and lines starting with # are skipped. Cognito emails each new user a temporary
# password; they choose a new one at their first sign-in. Existing users are left alone.
# The username is what the leaderboard shows, so don't use the email address as the username.
#
#   scripts/invite-users.sh users.txt      (or: make users USERS_FILE=users.txt)
set -euo pipefail

file="${1:?usage: scripts/invite-users.sh <file with lines: username email>}"
[ -f "$file" ] || { echo "error: $file not found" >&2; exit 1; }
cd "$(dirname "$0")/.."
REGION="us-east-1"

pool="$(terraform -chdir=terraform/foundation output -raw cognito_user_pool_id)"

created=0 skipped=0
while read -r username email _; do
  [ -n "${username:-}" ] && [ "${username:0:1}" != "#" ] || continue
  [ -n "${email:-}" ] || { echo "error: no email for $username" >&2; exit 1; }
  if aws cognito-idp admin-get-user --region "$REGION" --user-pool-id "$pool" \
    --username "$username" >/dev/null 2>&1; then
    echo "skip: $username already exists" >&2
    skipped=$((skipped + 1))
    continue
  fi
  aws cognito-idp admin-create-user --region "$REGION" --user-pool-id "$pool" \
    --username "$username" --desired-delivery-mediums EMAIL \
    --user-attributes Name=email,Value="$email" Name=email_verified,Value=true >/dev/null
  echo "invited: $username <$email>" >&2
  created=$((created + 1))
done <"$file"

echo "$created invited, $skipped already existed." >&2
