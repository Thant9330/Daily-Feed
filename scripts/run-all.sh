#!/bin/bash
set -euo pipefail

# Usage: bash run-all.sh <output_dir> <since_ts> <until_ts>
OUTPUT_DIR="${1:-data}"
SINCE_TS="${2:-$(date -d '24 hours ago' +%s 2>/dev/null || date -v-24H +%s)}"
UNTIL_TS="${3:-$(date +%s)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$OUTPUT_DIR"

SCRIPTS=(
  "fetch-github.sh"
  "fetch-hackernews.sh"
  "fetch-reddit.sh"
)

FAILED=0
SUCCEEDED=0

for SCRIPT in "${SCRIPTS[@]}"; do
  echo "→ ${SCRIPT}..."
  if bash "${SCRIPT_DIR}/${SCRIPT}" "$OUTPUT_DIR" "$SINCE_TS" "$UNTIL_TS"; then
    SUCCEEDED=$((SUCCEEDED + 1))
    echo "  ✓ done"
  else
    echo "  ✗ FAILED: ${SCRIPT}" >&2
    FAILED=$((FAILED + 1))
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) FAILED: ${SCRIPT}" >> "${OUTPUT_DIR}/fetch-errors.log"
  fi
done

echo "=== ${SUCCEEDED}/${#SCRIPTS[@]} sources succeeded ==="

# Exit non-zero only if ALL sources failed
if [[ "$SUCCEEDED" -eq 0 ]]; then
  echo "ERROR: all sources failed" >&2
  exit 1
fi

exit 0
