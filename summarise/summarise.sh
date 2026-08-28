#!/bin/bash
set -euo pipefail

# Prepare today's items for manual summarisation, then stop.
# The shell does ALL data handling; no LLM is ever called from here.
# Usage: bash summarise.sh [data_dir] [date]

DATA_DIR="${1:-data}"
DATE="${2:-$(date +%Y-%m-%d)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/prepare-items.sh" "$DATA_DIR" "$DATE"

cat >&2 << NEXT_STEPS

Next (manual):
  1. Paste the contents of ${DATA_DIR}/${DATE}/prompt.txt into your chat
  2. Save the JSON array it returns to ${DATA_DIR}/${DATE}/items.json
  3. bash summarise/build-feed.sh ${DATA_DIR}/${DATE}/items.json
NEXT_STEPS
