#!/usr/bin/env bash
# End-to-end smoke test of a Managed Agents self-hosted environment served by
# Tuist sandboxes: creates an agent and a session, waits for the first turn,
# lets the sandbox pause, then sends a second turn that must see the files
# the first one wrote.
#
#   ANTHROPIC_API_KEY=sk-ant-... ENVIRONMENT_ID=env_... \
#     infra/sandboxd/hack/managed-agents-smoke.sh
#
# Optional: MODEL (default claude-haiku-4-5-20251001, the cheapest supported
# model; the prompts are deliberately tiny), AGENT_ID (reuse an agent),
# BUDGET_CENTS (hard session spend cap, default 50), PAUSE_WAIT seconds
# between turns (default 90, longer than the worker's max idle plus the
# server's pause grace so the second turn hits a resume).
set -euo pipefail

: "${ANTHROPIC_API_KEY:?}"
: "${ENVIRONMENT_ID:?}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
BUDGET_CENTS="${BUDGET_CENTS:-50}"
PAUSE_WAIT="${PAUSE_WAIT:-90}"
API="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"

req() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -m 120 -X "$method" "$API$path" -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H 'anthropic-version: 2023-06-01' -H 'anthropic-beta: managed-agents-2026-04-01' \
      -H 'content-type: application/json' --data-binary "$body"
  else
    curl -sS -m 120 -X "$method" "$API$path" -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H 'anthropic-version: 2023-06-01' -H 'anthropic-beta: managed-agents-2026-04-01'
  fi
}

# Waits for a turn to finish: the event count must have grown past the
# given watermark and the session must be idle again. Checking idle alone
# races the queued message, which the session may not have picked up yet.
wait_turn() {
  local sid="$1" before="$2" status count
  for _ in $(seq 1 120); do
    status=$(req GET "/v1/sessions/$sid" | jq -r .status)
    count=$(event_count "$sid")
    if [ "$count" -gt "$before" ]; then
      case "$status" in
        idle|terminated) echo "session $sid is $status after $count events"; return 0 ;;
      esac
    fi
    sleep 5
  done
  echo "session $sid still $status after 10 minutes"; return 1
}

event_count() {
  req GET "/v1/sessions/$1/events?limit=200" | jq -r '(.data // .) | length'
}

print_turn() {
  # Agent messages and tool calls after the first $2 events.
  req GET "/v1/sessions/$1/events?limit=200" | jq -r --argjson skip "${2:-0}" '
    (.data // .) | .[$skip:] | .[] |
    if .type == "agent.message" then "agent: " + ([.content[]? | select(.type=="text") | .text] | join(" "))
    elif .type == "agent.tool_use" then "tool_use: " + (.name // .tool_name // "?") + " " + ((.input // {}) | tostring | .[0:160])
    elif .type == "user.tool_result" then "tool_result: " + ((.content // []) | tostring | .[0:200])
    elif .type == "session.status_idle" then "idle: " + ((.stop_reason // {}) | tostring)
    else empty end'
}

if [ -z "${AGENT_ID:-}" ]; then
  AGENT_ID=$(req POST /v1/agents "$(jq -n --arg m "$MODEL" '{name:"tuist-sandbox-smoke", model:$m, system:"Use bash. Reply with only the command output.", tools:[{type:"agent_toolset_20260401"}]}')" | jq -r .id)
fi
echo "agent: $AGENT_ID"

SID=$(req POST /v1/sessions "$(jq -n --arg a "$AGENT_ID" --arg e "$ENVIRONMENT_ID" --arg b "$BUDGET_CENTS" '{agent:$a, environment_id:$e, title:"tuist sandbox smoke", budget:{type:"limit", max_list_cost:{amount:$b, currency:"USD"}}, initial_events:[{type:"user.message", content:[{type:"text", text:"bash: hostname; date -u | tee /workspace/t"}]}]}')" | jq -r .id)
echo "session: $SID"

echo "== turn 1"; wait_turn "$SID" 1; print_turn "$SID" 0
seen=$(event_count "$SID")
echo "== waiting ${PAUSE_WAIT}s for the sandbox to pause"; sleep "$PAUSE_WAIT"
req POST "/v1/sessions/$SID/events" '{"events":[{"type":"user.message","content":[{"type":"text","text":"bash: cat /workspace/t; uptime"}]}]}' >/dev/null
echo "== turn 2"; wait_turn "$SID" "$((seen + 1))"; print_turn "$SID" "$seen"
echo "session: $SID"
