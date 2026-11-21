#!/usr/bin/env bash
# Offline checks of the state machine (CONVENTIONS §3), no AWS needed:
#   - renders like templatefile() and is valid JSON, QueryLanguage = JSONata
#   - every Task has a Catch and every Catch/Next points at a state that exists
#   - every state can reach a SESSION_ENDED sender, except the terminal states after them
set -euo pipefail

cd "$(dirname "$0")/.."
asl="$(scripts/sfn-render.sh)"

jq -e '.QueryLanguage == "JSONata"' >/dev/null <<<"$asl" \
  || { echo "error: QueryLanguage must be JSONata" >&2; exit 1; }

errors="$(jq -r '
  .States as $s
  | ($s | keys) as $names
  | [ $s | to_entries[]
      | .key as $k | .value as $v
      | ( if $v.Type == "Task" and (($v.Catch // []) | length) == 0 then "\($k): Task without Catch" else empty end ),
        ( [$v.Next, ($v.Catch // [])[].Next] | map(select(. != null))[]
          | select(($names | index(.)) == null) | "\($k): Next → unknown state \(.)" )
    ] | .[]' <<<"$asl")"

# States from which no SESSION_ENDED sender is reachable (walking Next and Catch).
unreachable="$(jq -r '
  .States as $s
  | def succ($n): [$s[$n].Next, ($s[$n].Catch // [])[].Next] | map(select(. != null));
    def senders: [$s | to_entries[] | select(.value.Arguments.MessageBody.type? == "SESSION_ENDED") | .key];
    def grow: (. + map(succ(.)[]) | unique) as $next
      | if ($next | length) == length then . else $next | grow end;
    def reach($n): [$n] | grow;
  senders as $send
  | $s | to_entries[]
  | select(.value.Type != "Succeed" and .value.Type != "Fail")
  | select((reach(.key) | map(. as $r | $send | index($r)) | map(select(. != null)) | length) == 0)
  | "\(.key): no path to a SESSION_ENDED sender"' <<<"$asl")"

if [ -n "$errors$unreachable" ]; then
  printf '%s\n' "$errors" "$unreachable" | sed '/^$/d' >&2
  exit 1
fi
echo "state machine: $(jq '.States | length' <<<"$asl") states, every Task has a Catch, every state can reach a SESSION_ENDED sender"
