#!/usr/bin/env bash
# Reads the Learner Lab "AWS CLI" block from stdin and writes it as the `default`
# profile in ~/.aws/credentials (other profiles are kept). Never prints the secrets.
#
#   scripts/lab-creds.sh            # paste the block; it stops reading once all 3 keys are in
#   pbpaste | scripts/lab-creds.sh
#
# Honors AWS_SHARED_CREDENTIALS_FILE, like the AWS CLI.
set -euo pipefail

CREDS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
REGION="us-east-1"

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

read_block() {
  if [[ -t 0 ]]; then
    log "Paste the Learner Lab \"AWS CLI\" block (AWS Details → AWS CLI → Show):"
  fi

  key_id="" secret="" token=""
  local line name value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ "$line" == *=* ]] || continue
    name="${line%%=*}"
    value="${line#*=}"
    name="${name//[[:space:]]/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$name" in
      aws_access_key_id)     key_id="$value" ;;
      aws_secret_access_key) secret="$value" ;;
      aws_session_token)     token="$value" ;;
    esac
    [[ -n "$key_id" && -n "$secret" && -n "$token" ]] && break
  done

  [[ -n "$key_id" ]] || die "aws_access_key_id not found in the pasted block"
  [[ -n "$secret" ]] || die "aws_secret_access_key not found in the pasted block"
  [[ -n "$token" ]]  || die "aws_session_token not found in the pasted block"
}

write_default_profile() {
  log "Writing the [default] profile to $CREDS_FILE"
  mkdir -p "$(dirname "$CREDS_FILE")"
  chmod 700 "$(dirname "$CREDS_FILE")"

  local tmp
  tmp="$(mktemp "${CREDS_FILE}.XXXXXX")"
  chmod 600 "$tmp"
  trap 'rm -f "$tmp"' EXIT

  # Keep every profile except the old [default].
  if [[ -f "$CREDS_FILE" ]]; then
    awk '
      /^[[:space:]]*\[/ { skip = ($0 ~ /^[[:space:]]*\[default\][[:space:]]*$/) }
      !skip
    ' "$CREDS_FILE" >"$tmp"
    [[ -s "$tmp" && "$(tail -c1 "$tmp")" != "" ]] && printf '\n' >>"$tmp"
  fi

  # printf is a builtin, so the secrets never show up in `ps`.
  printf '[default]\naws_access_key_id=%s\naws_secret_access_key=%s\naws_session_token=%s\n' \
    "$key_id" "$secret" "$token" >>"$tmp"

  mv "$tmp" "$CREDS_FILE"
  trap - EXIT
  chmod 600 "$CREDS_FILE"
}

check_identity() {
  log "Checking the credentials with sts get-caller-identity"
  local account
  account="$(aws sts get-caller-identity --profile default --region "$REGION" \
    --query Account --output text)" || die "credentials rejected by AWS; copy the block again from a running lab"
  log "OK: AWS account $account"
}

read_block
write_default_profile
check_identity
