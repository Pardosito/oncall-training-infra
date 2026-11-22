#!/usr/bin/env bash
# Local smoke test of the injector and the mock system on kind (INF-105). Plays the backend:
#   put a STARTING session in LocalStack → send FAULT (SCALE_TO_ZERO orders) to `faults`
#   → the injector scales orders to 0 and marks the session INCIDENT_ACTIVE
#   → gateway /health = 503 → scale orders back to the baseline → gateway /health = 200.
# Needs `make kind-up` and the backend's docker-compose (LocalStack on localhost:4566).
set -euo pipefail

CTX="kind-${KIND_CLUSTER:-oncall-training}"
ENDPOINT="${LOCALSTACK_URL:-http://localhost:4566}"
QUEUE="$ENDPOINT/000000000000/faults"
TABLE="Sessions"
BASELINE=2 # k8s/base/mock/deployment-orders.yaml
k() { kubectl --context "$CTX" "$@"; }
aws_l() { AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws --region us-east-1 --endpoint-url "$ENDPOINT" --output json "$@"; }
step() { echo "== $*" >&2; }
fail() { echo "error: $*" >&2; exit 1; }

# HTTP status of the gateway's /health, from inside its pod (the image has node but no curl;
# the API server's service proxy hides the status code).
gateway_health() {
  k -n mock exec deploy/gateway -- node -e \
    'fetch("http://localhost:8080/health").then((r) => console.log(r.status), () => console.log("down"))' \
    2>/dev/null || echo "?"
}
# until_ok <seconds> <description> <command...>: retries the command (a function, so its
# checks are evaluated on every try) until it succeeds.
until_ok() {
  local deadline=$((SECONDS + $1)) what="$2"
  shift 2
  until "$@"; do
    [ "$SECONDS" -lt "$deadline" ] || fail "timed out waiting for: $what"
    sleep 2
  done
}

k get ns mock >/dev/null 2>&1 || fail "no kind cluster ($CTX); run make kind-up"
aws_l sqs get-queue-attributes --queue-url "$QUEUE" --attribute-names QueueArn >/dev/null 2>&1 \
  || fail "no faults queue at $ENDPOINT; start the backend's docker-compose (LocalStack)"
[ "$(gateway_health)" = 200 ] || fail "gateway isn't healthy before the fault; check: kubectl --context $CTX -n mock get pods"

ts="$(date +%s)"
uid="local-smoke" sid="local-smoke-$ts"
key="{\"user_id\":{\"S\":\"$uid\"},\"session_id\":{\"S\":\"$sid\"}}"
restore() { k -n mock scale deploy/orders --replicas="$BASELINE" >/dev/null 2>&1 || true; aws_l dynamodb delete-item --table-name "$TABLE" --key "$key" >/dev/null 2>&1 || true; }
trap restore EXIT

step "session $sid: STARTING"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
aws_l dynamodb put-item --table-name "$TABLE" --item \
  "{\"user_id\":{\"S\":\"$uid\"},\"session_id\":{\"S\":\"$sid\"},\"username\":{\"S\":\"smoke\"},\"scenario_id\":{\"S\":\"orders-down\"},\"state\":{\"S\":\"STARTING\"},\"created_at\":{\"S\":\"$now\"},\"updated_at\":{\"S\":\"$now\"}}" >/dev/null

step "FAULT SCALE_TO_ZERO orders → faults"
body="$(jq -nc --arg s "$sid" --arg u "$uid" --arg f "fault-$ts" --arg t "$now" \
  '{faultId:$f, sessionId:$s, userId:$u, type:"SCALE_TO_ZERO", target:{namespace:"mock", deployment:"orders"}, sentAt:$t}')"
aws_l sqs send-message --queue-url "$QUEUE" --message-body "$body" >/dev/null

step "injector scales orders to 0"
orders_down() { [ "$(k -n mock get deploy orders -o jsonpath='{.status.replicas}')" = "" ]; }
until_ok 60 "orders at 0 replicas" orders_down

step "session INCIDENT_ACTIVE"
state() { aws_l dynamodb get-item --table-name "$TABLE" --key "$key" --consistent-read | jq -r '.Item.state.S'; }
active() { [ "$(state)" = INCIDENT_ACTIVE ]; }
until_ok 30 "session INCIDENT_ACTIVE" active

step "gateway /health = 503"
health_is() { [ "$(gateway_health)" = "$1" ]; }
until_ok 60 "gateway 503" health_is 503

step "revive: scale orders to $BASELINE"
k -n mock scale deploy/orders --replicas="$BASELINE" >/dev/null
k -n mock rollout status deploy/orders --timeout=120s >/dev/null

step "gateway /health = 200"
until_ok 60 "gateway 200" health_is 200

echo "local-smoke: ok — fault applied by the injector, system down, revived" >&2
