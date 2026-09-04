#!/usr/bin/env bash
# End-to-end smoke test of a Managed Agents self-hosted environment served by
# Tuist sandboxes: creates an agent and a session, waits for the first turn,
# lets the sandbox pause, then sends a second turn that must see the files
# the first one wrote.
#
#   ANTHROPIC_API_KEY=sk-ant-... ENVIRONMENT_ID=env_... \
#     infra/sandboxd/hack/managed-agents-smoke.sh
#
# Optional: MODEL (default claude-sonnet-5), AGENT_ID (reuse an agent),
# PAUSE_WAIT seconds between turns (default 120, longer than the worker's
# max idle plus the server's pause grace so the second turn hits a resume).
set -euo pipefail

: "${ANTHROPIC_API_KEY:?}"
: "${ENVIRONMENT_ID:?}"
MODEL="${MODEL:-claude-sonnet-5}"
PAUSE_WAIT="${PAUSE_WAIT:-120}"
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

wait_idle() {
  local sid="$1" status
  for _ in $(seq 1 120); do
    status=$(req GET "/v1/sessions/$sid" | jq -r .status)
    case "$status" in
      idle|terminated) echo "session $sid is $status"; return 0 ;;
    esac
    sleep 5
  done
  echo "session $sid still $status after 10 minutes"; return 1
}

print_turn() {
  # Agent messages and tool calls since the given event id (or all).
  req GET "/v1/sessions/$1/events?limit=200" | jq -r '
    (.data // .) | .[] |
    if .type == "agent.message" then "agent: " + ([.content[]? | select(.type=="text") | .text] | join(" "))
    elif .type == "agent.tool_use" then "tool_use: " + (.name // .tool_name // "?") + " " + ((.input // {}) | tostring | .[0:160])
    elif .type == "user.tool_result" then "tool_result: " + ((.content // []) | tostring | .[0:200])
    elif .type == "session.status_idle" then "idle: " + ((.stop_reason // {}) | tostring)
    else empty end'
}

if [ -z "${AGENT_ID:-}" ]; then
  AGENT_ID=$(req POST /v1/agents "$(jq -n --arg m "$MODEL" '{name:"tuist-sandbox-smoke", model:$m, system:"You are running inside a Tuist sandbox. Use the bash tool for every task and reply with the raw command output.", tools:[{type:"agent_toolset_20260401"}]}')" | jq -r .id)
fi
echo "agent: $AGENT_ID"

SID=$(req POST /v1/sessions "$(jq -n --arg a "$AGENT_ID" --arg e "$ENVIRONMENT_ID" '{agent:$a, environment_id:$e, title:"tuist sandbox smoke", initial_events:[{type:"user.message", content:[{type:"text", text:"Run exactly this with bash and reply with its output: uname -a; hostname; date -u | tee /workspace/hello.txt; nohup sleep 3600 >/dev/null 2>&1 & echo started sleep pid $!"}]}]}')" | jq -r .id)
echo "session: $SID"

echo "== turn 1"; wait_idle "$SID"; print_turn "$SID"
echo "== waiting ${PAUSE_WAIT}s for the sandbox to pause"; sleep "$PAUSE_WAIT"
req POST "/v1/sessions/$SID/events" '{"events":[{"type":"user.message","content":[{"type":"text","text":"Run exactly this with bash and reply with its output: cat /workspace/hello.txt; pgrep -a sleep; uptime"}]}]}' >/dev/null
echo "== turn 2"; wait_idle "$SID"; print_turn "$SID"
echo "session: $SID"
