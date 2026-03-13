#!/usr/bin/env bash
set -euo pipefail

LOG_DIR=".claude/logs"
RAW_LOG="${LOG_DIR}/tool-usage.log"
JSONL_LOG="${LOG_DIR}/tool-usage.jsonl"

mkdir -p "$LOG_DIR"

ts="$(date -Is)"
event="${CLAUDE_HOOK_EVENT:-unknown-event}"
cwd="$(pwd)"
user="$(id -un)"

stdin_file="$(mktemp)"
cat > "$stdin_file" || true

# -------------------------------
# RAW DEBUG LOG (your original)
# -------------------------------

{
  echo "===== ${ts} | event=${event} ====="
  echo "cwd: $cwd"
  echo "user: $user"
  echo "argv: $0 $*"

  if [[ -s "$stdin_file" ]]; then
    echo "--- stdin (raw) ---"
    cat "$stdin_file"
  else
    echo "--- stdin (raw) ---"
    echo "(empty)"
  fi

  echo
} >> "$RAW_LOG"

# -------------------------------
# Extract possible file paths
# -------------------------------

# crude but safe path detection
paths=$(grep -Eo '(\./|\../|/)?[A-Za-z0-9._/-]+\.(md|py|json|yaml|yml|toml|txt|sh)' "$stdin_file" || true)

# if no paths detected still log event
if [[ -z "$paths" ]]; then
  jq -n \
    --arg ts "$ts" \
    --arg event "$event" \
    --arg agent "${CLAUDE_AGENT:-unknown}" \
    --arg cwd "$cwd" \
    --arg user "$user" \
'{
  timestamp: $ts,
  event: $event,
  agent: $agent,
  cwd: $cwd,
  user: $user,
  path: null,
  exists: false,
  lines: null,
  chars: null,
  estimated_tokens: null
}' >> "$JSONL_LOG"
else

  for path in $paths; do
    if [[ -f "$path" ]]; then

      lines=$(wc -l < "$path" | tr -d ' ')
      chars=$(wc -c < "$path" | tr -d ' ')
      tokens=$((chars / 4))

      jq -n \
        --arg ts "$ts" \
        --arg event "$event" \
        --arg agent "${CLAUDE_AGENT:-unknown}" \
        --arg cwd "$cwd" \
        --arg user "$user" \
        --arg path "$path" \
        --argjson lines "$lines" \
        --argjson chars "$chars" \
        --argjson tokens "$tokens" \
'{
  timestamp: $ts,
  event: $event,
  agent: $agent,
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
        --arg agent "${CLAUDE_AGENT:-unknown}" \
        --arg cwd "$cwd" \
        --arg user "$user" \
        --arg path "$path" \
'{
  timestamp: $ts,
  event: $event,
  agent: $agent,
  cwd: $cwd,
  user: $user,
  path: $path,
  exists: false,
  lines: null,
  chars: null,
  estimated_tokens: null
}' >> "$JSONL_LOG"

    fi
  done

fi

rm -f "$stdin_file"
