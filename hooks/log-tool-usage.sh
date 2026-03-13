#!/usr/bin/env bash
set -euo pipefail

LOG_DIR=".claude/logs"
LOG_FILE="${LOG_DIR}/tool-usage.log"

mkdir -p "$LOG_DIR"

ts="$(date -Is)"
event="${CLAUDE_HOOK_EVENT:-unknown-event}"

# Capture stdin (Claude often sends JSON payload via stdin for hooks)
stdin_file="$(mktemp)"
cat > "$stdin_file" || true

{
  echo "===== ${ts} | event=${event} ====="
  echo "cwd: $(pwd)"
  echo "user: $(id -un)  uid=$(id -u)  gid=$(id -g)"
  echo "argv: $0 $*"
  if [[ -s "$stdin_file" ]]; then
    echo "--- stdin (raw) ---"
    cat "$stdin_file"
  else
    echo "--- stdin (raw) ---"
    echo "(empty)"
  fi
  echo
} >> "$LOG_FILE"

rm -f "$stdin_file"
