#!/bin/bash
# PostToolUse hook — validates JSON files written to data/
# Claude Code passes tool input as JSON on stdin

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.path // empty')

if [[ "$FILE" == data/*.json ]] || [[ "$FILE" == */data/*.json ]]; then
  if ! jq empty "$FILE" 2>/dev/null; then
    echo "ERROR: $FILE is not valid JSON" >&2
    exit 1
  fi
fi

exit 0
