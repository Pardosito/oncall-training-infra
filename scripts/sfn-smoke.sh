#!/usr/bin/env bash
# One end-to-end execution of the deployed state machine in the lab (INF-048). This script plays
# the backend api, the injector and the worker:
#   put a STARTING item → StartExecution → take the FAULT from `faults` → mark INCIDENT_ACTIVE
#   → take AWAIT_FIX from user-actions.fifo → answer the task token → check the item and SESSION_ENDED
# SMOKE_PATH picks the ending: resolve (SendTaskSuccess, default) | abandon (SendTaskFailure)
# | timeout (no answer; maxResolveSeconds = 10).
# Run it with nothing else consuming the queues (cluster down, or injector and worker at 0 replicas),
# otherwise they take the messages first. The test item is deleted at the end.
set -euo pipefail

cd "$(dirname "$0")/.."
REGION="us-east-1"
path="${SMOKE_PATH:-resolve}"
case "$path" in resolve | abandon | timeout) ;; *) echo "error: SMOKE_PATH must be resolve, abandon or timeout" >&2; exit 1 ;; esac

out="$(terraform -chdir=terraform/foundation output -json)"
get() { jq -r --arg k "$1" '.[$k].value // empty' <<<"$out"; }
sm="$(get state_machine_arn)"
faults="$(get faults_queue_url)"
actions="$(get user_actions_queue_url)"
table="$(get sessions_table)"
[ -n "$sm" ] || { echo "error: no state_machine_arn output; run make foundation-apply first" >&2; exit 1; }

# Refuse to race the real consumers when the cluster is reachable.
for ns_deploy in injector/injector app/worker; do
  replicas="$(kubectl --request-timeout=10s -n "${ns_deploy%/*}" get deploy "${ns_deploy#*/}" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  if [ -n "$replicas" ] && [ "$replicas" != "0" ]; then
    echo "error: $ns_deploy is running ($replicas replicas) and would consume the smoke messages." >&2
    echo "Run with the cluster down, or: kubectl -n ${ns_deploy%/*} scale deploy/${ns_deploy#*/} --replicas=0" >&2
    exit 1
  fi
done

ts="$(date +%s)"
uid="smoke"
sid="smoke-$ts"
key="{\"user_id\":{\"S\":\"$uid\"},\"session_id\":{\"S\":\"$sid\"}}"
max_resolve=120
[ "$path" != timeout ] || max_resolve=10
cleanup() { aws dynamodb delete-item --region "$REGION" --table-name "$table" --key "$key" >/dev/null 2>&1 || true; }
trap cleanup EXIT

aws_q() { aws --region "$REGION" --output json "$@"; }

# take <queue> <jq filter on the parsed body>: receives until a matching message shows up,
# deletes it and prints its body. Other messages are made visible again right away.
take() {
  local queue="$1" match="$2" deadline=$((SECONDS + 90)) msgs n i body handle
  while [ "$SECONDS" -lt "$deadline" ]; do
    msgs="$(aws_q sqs receive-message --queue-url "$queue" --max-number-of-messages 10 --wait-time-seconds 10)"
    n="$(jq '.Messages // [] | length' <<<"$msgs")"
    for ((i = 0; i < n; i++)); do
      body="$(jq -r --argjson i "$i" '.Messages[$i].Body' <<<"$msgs")"
      handle="$(jq -r --argjson i "$i" '.Messages[$i].ReceiptHandle' <<<"$msgs")"
      if jq -e "$match" >/dev/null 2>&1 <<<"$body"; then
        aws_q sqs delete-message --queue-url "$queue" --receipt-handle "$handle" >/dev/null
        printf '%s' "$body"
        return 0
      fi
      aws_q sqs change-message-visibility --queue-url "$queue" --receipt-handle "$handle" --visibility-timeout 0 >/dev/null
    done
  done
  echo "error: no message matching $match on $queue within 90 s" >&2
  return 1
}

step() { echo "== $*" >&2; }

step "session $sid (path: $path)"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
aws_q dynamodb put-item --table-name "$table" --condition-expression "attribute_not_exists(session_id)" --item \
  "{\"user_id\":{\"S\":\"$uid\"},\"session_id\":{\"S\":\"$sid\"},\"username\":{\"S\":\"smoke\"},\"scenario_id\":{\"S\":\"orders-down\"},\"state\":{\"S\":\"STARTING\"},\"created_at\":{\"S\":\"$now\"},\"updated_at\":{\"S\":\"$now\"}}" >/dev/null

input="$(jq -nc --arg u "$uid" --arg s "$sid" --arg f "fault-$ts" --argjson m "$max_resolve" \
  '{userId:$u, sessionId:$s, scenarioId:"orders-down", warmupSeconds:1, maxResolveSeconds:$m,
    fault:{faultId:$f, type:"SCALE_TO_ZERO", target:{namespace:"mock", deployment:"orders"}}}')"
exec_arn="$(aws_q stepfunctions start-execution --state-machine-arn "$sm" --name "$sid" --input "$input" | jq -r .executionArn)"
step "execution started: $exec_arn"

step "FAULT on faults"
fault="$(take "$faults" ".sessionId == \"$sid\"")"
jq -e --arg f "fault-$ts" '.faultId == $f and .userId == "smoke" and .type == "SCALE_TO_ZERO" and (.sentAt | length > 0)' >/dev/null <<<"$fault" \
  || { echo "error: unexpected FAULT: $fault" >&2; exit 1; }

step "injector stand-in: STARTING → INCIDENT_ACTIVE"
aws_q dynamodb update-item --table-name "$table" --key "$key" \
  --update-expression "SET #s = :a, fault_injected_at = :t" --condition-expression "#s = :st" \
  --expression-attribute-names '{"#s":"state"}' \
  --expression-attribute-values "{\":a\":{\"S\":\"INCIDENT_ACTIVE\"},\":st\":{\"S\":\"STARTING\"},\":t\":{\"S\":\"$now\"}}" >/dev/null

step "AWAIT_FIX on user-actions.fifo"
await="$(take "$actions" ".type == \"AWAIT_FIX\" and .sessionId == \"$sid\"")"
token="$(jq -r .taskToken <<<"$await")"
[ -n "$token" ] && [ "$token" != null ] || { echo "error: AWAIT_FIX has no taskToken" >&2; exit 1; }

case "$path" in
  resolve)
    step "worker stand-in: SendTaskSuccess"
    aws_q stepfunctions send-task-success --task-token "$token" --task-output \
      "{\"resolvedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"ttdSeconds\":42,\"ttrSeconds\":131,\"wrongActions\":1,\"actionsCount\":4,\"score\":802}" >/dev/null
    want_exec=SUCCEEDED want_state=RESOLVED want_outcome=RESOLVED want_reason=null ;;
  abandon)
    step "worker stand-in: SendTaskFailure(Abandoned)"
    aws_q stepfunctions send-task-failure --task-token "$token" --error Abandoned --cause "smoke test" >/dev/null
    want_exec=FAILED want_state=FAILED want_outcome=FAILED want_reason=ABANDONED ;;
  timeout)
    step "no answer; waiting for the ${max_resolve} s timeout"
    want_exec=FAILED want_state=FAILED want_outcome=FAILED want_reason=TIMEOUT ;;
esac

step "SESSION_ENDED on user-actions.fifo"
ended="$(take "$actions" ".type == \"SESSION_ENDED\" and .sessionId == \"$sid\"")"
jq -e --arg o "$want_outcome" --arg r "$want_reason" '.outcome == $o and ((.reason // "null") == $r)' >/dev/null <<<"$ended" \
  || { echo "error: unexpected SESSION_ENDED: $ended" >&2; exit 1; }

step "execution status"
for _ in $(seq 1 20); do
  status="$(aws_q stepfunctions describe-execution --execution-arn "$exec_arn" | jq -r .status)"
  [ "$status" = RUNNING ] || break
  sleep 1
done
[ "$status" = "$want_exec" ] || { echo "error: execution is $status, want $want_exec" >&2; exit 1; }

step "session item"
item="$(aws_q dynamodb get-item --table-name "$table" --key "$key" --consistent-read | jq .Item)"
jq -e --arg s "$want_state" '.state.S == $s and (.ended_at.S | length > 0) and (.task_token == null)' >/dev/null <<<"$item" \
  || { echo "error: unexpected item: $item" >&2; exit 1; }
if [ "$path" = resolve ]; then
  jq -e '.score.N == "802" and .ttd_seconds.N == "42" and .ttr_seconds.N == "131"' >/dev/null <<<"$item" \
    || { echo "error: score fields missing: $item" >&2; exit 1; }
else
  jq -e --arg r "$want_reason" '.failure_reason.S == $r' >/dev/null <<<"$item" \
    || { echo "error: failure_reason missing: $item" >&2; exit 1; }
fi

echo "sfn-smoke ($path): ok — execution $want_exec, item $want_state, SESSION_ENDED $want_outcome" >&2
