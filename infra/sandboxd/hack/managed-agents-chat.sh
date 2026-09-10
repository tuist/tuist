#!/usr/bin/env bash
# Interactive terminal chat with a Managed Agents session whose tools run in
# a Tuist sandbox (a self_hosted environment). Each line you type is one
# turn; the script prints the agent's tool calls, their results and its
# replies as they land. Leave it idle for a minute or two between turns to
# watch the sandbox pause and resume underneath the same session.
#
#   ANTHROPIC_API_KEY=sk-ant-api... ENVIRONMENT_ID=env_... \
#     infra/sandboxd/hack/managed-agents-chat.sh
#
# Optional: MODEL (default claude-sonnet-5), BUDGET_CENTS (hard session cap,
# default 200), SESSION_ID (resume an existing session instead of creating
# one), AGENT_ID (reuse an agent; otherwise one is created and its id cached
# in .claude/tmp/managed-agents-chat.agent).
set -euo pipefail

: "${ANTHROPIC_API_KEY:?}"
: "${ENVIRONMENT_ID:?}"
MODEL="${MODEL:-claude-sonnet-5}"
BUDGET_CENTS="${BUDGET_CENTS:-200}"
API="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
CACHE_DIR="${CACHE_DIR:-.claude/tmp}"

BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
RESET=$(printf '\033[0m')

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

events() {
  req GET "/v1/sessions/$1/events?limit=1000" | jq -c '(.data // .)'
}

# Prints events past index $2 in a readable form and echoes the new count.
print_new() {
  local sid="$1" seen="$2" all
  all=$(events "$sid")
  echo "$all" | jq -r --argjson skip "$seen" --arg b "$BOLD" --arg d "$DIM" --arg r "$RESET" '.[$skip:] | .[] |
    if .type == "agent.message" then $b + "agent: " + $r + ([.content[]? | select(.type=="text") | .text] | join("\n"))
    elif .type == "agent.tool_use" then $d + "$ " + ((.input.command // (.input|tostring)) | .[0:400]) + $r
    elif .type == "user.tool_result" then $d + (([.content[]? | select(.type=="text") | .text] | join("")) | .[0:1200]) + $r
    elif .type == "session.status_idle" then $d + "[idle: " + (.stop_reason.type // "") + "]" + $r
    else empty end' >&2
  echo "$all" | jq -r 'length'
}

# Waits for the turn started after index $2 to reach a terminal idle.
wait_turn() {
  local sid="$1" seen="$2" all count last
  for _ in $(seq 1 360); do
    all=$(events "$sid")
    count=$(echo "$all" | jq -r 'length')
    if [ "$count" -gt "$seen" ]; then
      last=$(echo "$all" | jq -r --argjson skip "$seen" '[.[$skip:] | .[] | select(.type=="session.status_idle") | .stop_reason.type] | last // ""')
      case "$last" in
        end_turn|budget_reached|retries_exhausted) return 0 ;;
      esac
    fi
    sleep 2
  done
  echo "turn did not finish within 12 minutes" >&2
}

mkdir -p "$CACHE_DIR"
if [ -z "${AGENT_ID:-}" ] && [ -f "$CACHE_DIR/managed-agents-chat.agent" ]; then
  AGENT_ID=$(cat "$CACHE_DIR/managed-agents-chat.agent")
fi
if [ -z "${AGENT_ID:-}" ]; then
  AGENT_ID=$(req POST /v1/agents "$(jq -n --arg m "$MODEL" '{name:"tuist-sandbox-chat", model:$m, system:"You are a coding agent working inside a Linux sandbox. Your working directory is /workspace and it persists across turns. Use bash for anything that touches the machine. Be concise.", tools:[{type:"agent_toolset_20260401"}]}')" | jq -r .id)
  echo "$AGENT_ID" > "$CACHE_DIR/managed-agents-chat.agent"
fi

if [ -z "${SESSION_ID:-}" ]; then
  SESSION_ID=$(req POST /v1/sessions "$(jq -n --arg a "$AGENT_ID" --arg e "$ENVIRONMENT_ID" --arg b "$BUDGET_CENTS" '{agent:$a, environment_id:$e, title:"tuist sandbox chat", budget:{type:"limit", max_list_cost:{amount:$b, currency:"USD"}}}')" | jq -r .id)
fi
echo "agent $AGENT_ID, session $SESSION_ID (budget ${BUDGET_CENTS}c, model $MODEL)" >&2
echo "trace: platform.claude.com, Sessions, $SESSION_ID" >&2
echo "type a message and press enter; ctrl-d to quit" >&2

seen=$(print_new "$SESSION_ID" 0)
while IFS= read -r -p "${BOLD}you:${RESET} " line; do
  [ -n "$line" ] || continue
  req POST "/v1/sessions/$SESSION_ID/events" "$(jq -n --arg t "$line" '{events:[{type:"user.message", content:[{type:"text", text:$t}]}]}')" >/dev/null
  wait_turn "$SESSION_ID" "$seen"
  seen=$(print_new "$SESSION_ID" "$seen")
done
echo >&2
echo "session $SESSION_ID left idle; resume it later with SESSION_ID=$SESSION_ID" >&2
