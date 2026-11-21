#!/usr/bin/env bash
# TestState checks for each state of the scenario state machine (INF-047, CONVENTIONS §3).
# Cases live in statemachines/tests/cases.json. Task states are mocked, so nothing is sent to SQS
# or written to DynamoDB; it only needs valid lab credentials for the TestState API itself.
#   scripts/sfn-test.sh [case name filter]
set -euo pipefail

cd "$(dirname "$0")/.."
REGION="us-east-1"
CASES="statemachines/tests/cases.json"
filter="${1:-}"

indent() { while IFS= read -r line; do echo "      $line" >&2; done <<<"$1"; }

definition="$(scripts/sfn-render.sh | jq -c .)"

echo "== validate-state-machine-definition" >&2
validation="$(aws stepfunctions validate-state-machine-definition --region "$REGION" \
  --type STANDARD --definition "$definition" --output json)"
if [ "$(jq -r .result <<<"$validation")" != "OK" ]; then
  jq . <<<"$validation" >&2
  exit 1
fi
echo "ok" >&2

pass=0
fail=0
count="$(jq '.cases | length' "$CASES")"
for i in $(seq 0 $((count - 1))); do
  case_json="$(jq -c --argjson i "$i" '
    . as $root | .cases[$i]
    | .variables = (if .noVariables then null else ($root.variables + (.extraVariables // {})) end)
    | .context = $root.context' "$CASES")"
  name="$(jq -r .name <<<"$case_json")"
  [ -z "$filter" ] || [[ "$name" == *"$filter"* ]] || continue

  args=(--region "$REGION" --output json --inspection-level DEBUG
    --definition "$definition" --state-name "$(jq -r .state <<<"$case_json")"
    --input "$(jq -c '.input // {}' <<<"$case_json")")
  if [ "$(jq -r '.variables != null' <<<"$case_json")" = "true" ]; then
    args+=(--variables "$(jq -c .variables <<<"$case_json")")
  fi
  if [ "$(jq -r '.mock != null' <<<"$case_json")" = "true" ]; then
    # mock.result is a JSON string in the API; PRESENT checks the fields we give against the SDK model.
    args+=(--mock "$(jq -c '.mock | if .result then .result |= tojson else . end | .fieldValidationMode = "PRESENT"' <<<"$case_json")")
    args+=(--context "$(jq -c .context <<<"$case_json")")
  fi
  if [ "$(jq -r '.retrierRetryCount != null' <<<"$case_json")" = "true" ]; then
    args+=(--state-configuration "retrierRetryCount=$(jq -r .retrierRetryCount <<<"$case_json")")
  fi

  if ! res="$(aws stepfunctions test-state "${args[@]}" 2>&1)"; then
    echo "FAIL  $name" >&2
    indent "$res"
    fail=$((fail + 1))
    continue
  fi

  # Compare what we expect against status, nextState, the variables after the state and the
  # arguments it rendered (inspectionData fields are JSON strings).
  verdict="$(jq -r --argjson exp "$(jq -c .expect <<<"$case_json")" '
    def parsed($f): (.inspectionData[$f] // "null") | (try fromjson catch .);
    [ (if $exp.status and .status != $exp.status then "status \(.status), want \($exp.status)" else empty end),
      (if $exp.nextState and .nextState != $exp.nextState then "nextState \(.nextState), want \($exp.nextState)" else empty end),
      (if $exp.variables and ((parsed("variables") // {}) | contains($exp.variables) | not)
         then "variables \(parsed("variables") | tojson)" else empty end),
      (if $exp.arguments and ((parsed("afterArguments") // {}) | contains($exp.arguments) | not)
         then "arguments \(parsed("afterArguments") | tojson)" else empty end)
    ] | join("\n")' <<<"$res")"

  if [ -z "$verdict" ]; then
    echo "ok    $name" >&2
    pass=$((pass + 1))
  else
    echo "FAIL  $name" >&2
    indent "$verdict"
    [ -z "${SFN_TEST_DEBUG:-}" ] || jq . <<<"$res" >&2
    fail=$((fail + 1))
  fi
done

echo "sfn-test: $pass passed, $fail failed" >&2
[ "$fail" -eq 0 ]
