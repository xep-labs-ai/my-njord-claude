#!/usr/bin/env bash
set -euo pipefail

LOG_DIR=".claude/logs"
RAW_LOG="${LOG_DIR}/tool-usage.log"
JSONL_LOG="${LOG_DIR}/tool-usage.jsonl"

mkdir -p "$LOG_DIR"

ts="$(date -Is)"
cwd="$(pwd)"
user="$(id -un)"

stdin_data="$(cat)"

# -------------------------------
# Parse fields from JSON stdin
# -------------------------------

event="$(echo "$stdin_data" | jq -r '.hook_event_name // "unknown-event"')"
tool_name="$(echo "$stdin_data" | jq -r '.tool_name // "unknown"')"
session_id="$(echo "$stdin_data" | jq -r '.session_id // "unknown"')"
transcript_path="$(echo "$stdin_data" | jq -r '.transcript_path // ""')"

# agent: prefer env var (set by subagent contexts), fall back to session_id
agent="${CLAUDE_AGENT:-}"
if [[ -z "$agent" ]]; then
  agent="session:${session_id}"
fi

# Extract agent_model and agent_effort from the most recent assistant entry in the transcript
agent_model="unknown"
agent_effort="unknown"
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  transcript_fields="$(tail -n 200 "$transcript_path" | python3 -c "
import sys, json
model = None
effort = None
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        msg = obj.get('message', {})
        if isinstance(msg, dict) and 'model' in msg:
            model = msg['model']
            effort = msg.get('usage', {}).get('service_tier', None)
    except Exception:
        pass
print(json.dumps({'model': model or 'unknown', 'effort': effort or 'unknown'}))
" 2>/dev/null || echo '{"model":"unknown","effort":"unknown"}')"
  agent_model="$(echo "$transcript_fields" | jq -r '.model')"
  agent_effort="$(echo "$transcript_fields" | jq -r '.effort')"
fi

# -------------------------------
# RAW DEBUG LOG
# -------------------------------

{
  echo "===== ${ts} | event=${event} | tool=${tool_name} ====="
  echo "cwd: $cwd"
  echo "user: $user"
  echo "agent: $agent"
  echo "agent_model: $agent_model | agent_effort: $agent_effort"
  echo "argv: $0 $*"

  if [[ -n "$stdin_data" ]]; then
    echo "--- stdin (raw) ---"
    echo "$stdin_data"
  else
    echo "--- stdin (raw) ---"
    echo "(empty)"
  fi

  echo
} >> "$RAW_LOG"

# -------------------------------
# Extract primary path from tool_input
# -------------------------------

path="$(echo "$stdin_data" | jq -r '
  .tool_input |
  if type == "object" then
    (.file_path // .path // null)
  else
    null
  end
')"

# Emit one JSONL record
if [[ "$path" != "null" && -n "$path" ]]; then
  if [[ -f "$path" ]]; then
    lines=$(wc -l < "$path" | tr -d ' ')
    chars=$(wc -c < "$path" | tr -d ' ')
    tokens=$((chars / 4))

    jq -n \
      --arg ts "$ts" \
      --arg event "$event" \
      --arg tool_name "$tool_name" \
      --arg agent "$agent" \
      --arg agent_model "$agent_model" \
      --arg agent_effort "$agent_effort" \
      --arg session_id "$session_id" \
      --arg cwd "$cwd" \
      --arg user "$user" \
      --arg path "$path" \
      --argjson lines "$lines" \
      --argjson chars "$chars" \
      --argjson tokens "$tokens" \
'{
  timestamp: $ts,
  event: $event,
  tool_name: $tool_name,
  agent: $agent,
  agent_model: $agent_model,
  agent_effort: $agent_effort,
  session_id: $session_id,
  cwd: $cwd,
  user: $user,
  path: $path,
  exists: true,
  lines: $lines,
  chars: $chars,
  estimated_tokens: $tokens
}' >> "$JSONL_LOG"

  else
    jq -n \
      --arg ts "$ts" \
      --arg event "$event" \
      --arg tool_name "$tool_name" \
      --arg agent "$agent" \
      --arg agent_model "$agent_model" \
      --arg agent_effort "$agent_effort" \
      --arg session_id "$session_id" \
      --arg cwd "$cwd" \
      --arg user "$user" \
      --arg path "$path" \
'{
  timestamp: $ts,
  event: $event,
  tool_name: $tool_name,
  agent: $agent,
  agent_model: $agent_model,
  agent_effort: $agent_effort,
  session_id: $session_id,
  cwd: $cwd,
  user: $user,
  path: $path,
  exists: false,
  lines: null,
  chars: null,
  estimated_tokens: null
}' >> "$JSONL_LOG"

  fi
else
  jq -n \
    --arg ts "$ts" \
    --arg event "$event" \
    --arg tool_name "$tool_name" \
    --arg agent "$agent" \
    --arg agent_model "$agent_model" \
    --arg agent_effort "$agent_effort" \
    --arg session_id "$session_id" \
    --arg cwd "$cwd" \
    --arg user "$user" \
'{
  timestamp: $ts,
  event: $event,
  tool_name: $tool_name,
  agent: $agent,
  agent_model: $agent_model,
  agent_effort: $agent_effort,
  session_id: $session_id,
  cwd: $cwd,
  user: $user,
  path: null,
  exists: false,
  lines: null,
  chars: null,
  estimated_tokens: null
}' >> "$JSONL_LOG"

fi
