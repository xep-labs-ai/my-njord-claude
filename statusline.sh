#!/usr/bin/env bash
set -euo pipefail

# Requires: jq
input="$(cat)"

MODEL="$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')"
DIR="$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')"
PCT="$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)"
COST="$(echo "$input" | jq -r '.cost.total_cost_usd // 0')"
COST_FMT="$(printf '$%.2f' "$COST")"

TRANSCRIPT="$(echo "$input" | jq -r '.transcript_path // empty')"
CACHE_DIR=".claude/cache"
STATE_FILE="${CACHE_DIR}/statusline_state.json"
mkdir -p "$CACHE_DIR"

# State schema:
# { "last_line": 0, "by_agent": { "main": { "in":0, "out":0, "total":0 }, ... } }

if [[ -f "$STATE_FILE" ]]; then
  last_line="$(jq -r '.last_line // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
else
  last_line=0
  echo '{"last_line":0,"by_agent":{}}' > "$STATE_FILE"
fi

declare -A inTok outTok totalTok

# Load existing totals into bash maps
while IFS=$'\t' read -r agent jin jout jtotal; do
  [[ -z "$agent" ]] && continue
  inTok["$agent"]="$jin"
  outTok["$agent"]="$jout"
  totalTok["$agent"]="$jtotal"
done < <(
  jq -r '
    (.by_agent // {}) | to_entries[] |
    "\(.key)\t\(.value.in // 0)\t\(.value.out // 0)\t\(.value.total // 0)"
  ' "$STATE_FILE" 2>/dev/null || true
)

# Incrementally parse transcript, if available
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  cur_lines="$(wc -l < "$TRANSCRIPT" | tr -d ' ')"
  if [[ "$cur_lines" -gt "$last_line" ]]; then
    start_line=$((last_line + 1))

    # Process only new JSONL lines
    tail -n +"$start_line" "$TRANSCRIPT" \
      | jq -r '
          # Be resilient to schema changes:
          # - agent name may live in .agent.name, .agent, .metadata.agent, etc.
          # - usage may live in .usage.input_tokens/output_tokens/total_tokens
          def agentname:
            (.agent.name // .agent // .metadata.agent // .metadata.agent_name // "main") | tostring;

          def inTok:
            (.usage.input_tokens // .usage.inputTokens // .usage.prompt_tokens // 0) | tonumber;

          def outTok:
            (.usage.output_tokens // .usage.outputTokens // .usage.completion_tokens // 0) | tonumber;

          def totalTok:
            (.usage.total_tokens // .usage.totalTokens // (inTok + outTok)) | tonumber;

          select(type=="object")
          | "\(agentname)\t\(inTok)\t\(outTok)\t\(totalTok)"
        ' 2>/dev/null \
      | while IFS=$'\t' read -r agent di do dt; do
          [[ -z "$agent" ]] && agent="main"
          inTok["$agent"]=$(( ${inTok["$agent"]:-0} + di ))
          outTok["$agent"]=$(( ${outTok["$agent"]:-0} + do ))
          totalTok["$agent"]=$(( ${totalTok["$agent"]:-0} + dt ))
        done

    last_line="$cur_lines"

    # Write updated state
    {
      echo -n '{"last_line":'
      echo -n "$last_line"
      echo -n ',"by_agent":{'

      first=1
      for agent in "${!totalTok[@]}"; do
        [[ $first -eq 0 ]] && echo -n ','
        first=0
        printf '"%s":{"in":%s,"out":%s,"total":%s}' \
          "$(printf '%s' "$agent" | jq -Rr @json | sed 's/^"//;s/"$//')" \
          "${inTok["$agent"]:-0}" \
          "${outTok["$agent"]:-0}" \
          "${totalTok["$agent"]:-0}"
      done

      echo '}}'
    } > "$STATE_FILE"
  fi
fi

# Build a compact per-agent summary (sorted by total desc)
# Show top 3 to keep it readable.
agent_summary="$(
  for a in "${!totalTok[@]}"; do
    printf "%s\t%s\n" "$a" "${totalTok["$a"]}"
  done \
  | sort -k2,2nr \
  | head -n 3 \
  | awk -F'\t' '{printf "%s:%s ", $1, $2}'
)"

# Nice short dir name
base="${DIR##*/}"

# Output two lines (Claude supports multi-line)
echo "[$MODEL] ${base} | ctx:${PCT}% | cost:${COST_FMT}"
echo "tokens: ${agent_summary:-main:0 }"

