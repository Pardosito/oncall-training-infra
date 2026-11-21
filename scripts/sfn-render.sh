#!/usr/bin/env bash
# Renders statemachines/scenario.asl.json the way Terraform's templatefile() does, for checks
# that run outside Terraform (make lint-sfn, make sfn-test). Defaults are dummy values.
#   scripts/sfn-render.sh [faults_queue_url] [user_actions_queue_url] [sessions_table]
set -euo pipefail

cd "$(dirname "$0")/.."
faults="${1:-https://sqs.us-east-1.amazonaws.com/000000000000/oncall-training-faults}"
user_actions="${2:-https://sqs.us-east-1.amazonaws.com/000000000000/oncall-training-user-actions.fifo}"
table="${3:-Sessions}"

asl="$(cat statemachines/scenario.asl.json)"
asl="${asl//\$\{faults_queue_url\}/$faults}"
asl="${asl//\$\{user_actions_queue_url\}/$user_actions}"
asl="${asl//\$\{sessions_table\}/$table}"

# templatefile() would fail on any other ${...} or %{...}; so do we.
if grep -qE '\$\{|%\{' <<<"$asl"; then
  echo "error: unknown template placeholder in scenario.asl.json:" >&2
  grep -noE '\$\{[^}]*\}|%\{[^}]*\}' <<<"$asl" >&2
  exit 1
fi
jq . <<<"$asl"
