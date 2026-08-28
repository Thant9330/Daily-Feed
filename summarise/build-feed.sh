#!/bin/bash
set -euo pipefail

# Rebuild the feed from a summarised JSON array.
# This script NEVER calls an LLM — it is the shell half after the manual gap:
#   (you paste the chat's reply into items.json)  →  build-feed.sh  →  feed.json + feed.md
# The input must be a plain JSON array. Strip any code fences yourself before saving it.
# Usage: bash build-feed.sh <items_json> [data_dir] [date]

ITEMS_JSON="${1:?usage: bash build-feed.sh <items_json> [data_dir] [date]}"
DATA_DIR="${2:-data}"
DATE="${3:-$(date +%Y-%m-%d)}"
ARCHIVE_DIR="${DATA_DIR}/${DATE}"
NORMALISED="${ARCHIVE_DIR}/.items-normalised.json"

if [[ ! -f "$ITEMS_JSON" ]]; then
  echo "ERROR: ${ITEMS_JSON} not found" >&2
  exit 1
fi

# ── Validate: must be a plain JSON array ─────────────────────────────────────
if ! jq empty "$ITEMS_JSON" 2>/dev/null; then
  echo "ERROR: ${ITEMS_JSON} is not valid JSON." >&2
  echo "       If the reply came wrapped in a code fence, remove the \`\`\` lines and re-save." >&2
  exit 1
fi

ACTUAL_TYPE=$(jq -r 'type' "$ITEMS_JSON")
if [[ "$ACTUAL_TYPE" != "array" ]]; then
  echo "ERROR: ${ITEMS_JSON} must be a JSON array, found: ${ACTUAL_TYPE}" >&2
  exit 1
fi

mkdir -p "$ARCHIVE_DIR"
trap 'rm -f "$NORMALISED"' EXIT

# ── Ensure required fields and correct defaults ──────────────────────────────
jq '[.[] | {
  id: (.id // ("item-" + (env.RANDOM // "0"))),
  source: (.source // "unknown"),
  title: (.title // "Untitled"),
  url: (.url // ""),
  summary: (.summary // ""),
  tags: (if .tags | type == "array" then .tags else [] end),
  relevance: (if .relevance then (.relevance | tonumber | floor) else 3 end),
  read: false,
  bookmarked: false
}]' "$ITEMS_JSON" > "$NORMALISED"

# ── Write feed.json ───────────────────────────────────────────────────────────
# --slurpfile reads the items from a file; passing them with --argjson would
# blow the ~32KB argv limit once the feed grows past ~55 items.
# FEED_NOTE marks a feed as provisional (see build-raw-feed.sh). Its presence is
# what tells a later run the feed on disk is safe to overwrite; real summaries
# leave it unset, so they are never clobbered.
jq -n \
  --arg date "$DATE" \
  --arg note "${FEED_NOTE:-}" \
  --slurpfile items "$NORMALISED" \
  '{"date": $date, "items": $items[0]}
   | if $note == "" then . else .note = $note end' > "${DATA_DIR}/feed.json"
echo "Written: ${DATA_DIR}/feed.json" >&2

# ── Write feed.md (human-readable, assembled by shell/jq) ────────────────────
{
  echo "# Daily Feed — ${DATE}"
  echo ""

  if [[ -n "${FEED_NOTE:-}" ]]; then
    echo "> ${FEED_NOTE}"
    echo ""
  fi

  for SRC in github hackernews reddit; do
    SRC_LABEL=$(echo "$SRC" | sed 's/hackernews/Hacker News/;s/github/GitHub/;s/reddit/Reddit/')
    SRC_ITEMS=$(jq -r --arg s "$SRC" '[.[] | select(.source == $s)] | length' "$NORMALISED")
    if [[ "$SRC_ITEMS" -gt 0 ]]; then
      echo "## ${SRC_LABEL} (${SRC_ITEMS} items)"
      echo ""
      jq -r --arg s "$SRC" '
        .[] | select(.source == $s) |
        "### \(.title)\n\(.url)\n\n\(.summary)\n\nTags: \(.tags | join(", ")) | Relevance: \(.relevance)/5\n"
      ' "$NORMALISED"
    fi
  done
} > "${DATA_DIR}/feed.md"
echo "Written: ${DATA_DIR}/feed.md" >&2

# ── Archive ───────────────────────────────────────────────────────────────────
cp "${DATA_DIR}/feed.json" "${ARCHIVE_DIR}/feed.json"
cp "${DATA_DIR}/feed.md"   "${ARCHIVE_DIR}/feed.md"
echo "Archived to: ${ARCHIVE_DIR}/" >&2

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$(jq 'length' "$NORMALISED")
echo "" >&2
echo "=== Feed built for ${DATE} ===" >&2
echo "  Total items: $TOTAL" >&2
for SRC in github hackernews reddit; do
  N=$(jq --arg s "$SRC" '[.[] | select(.source == $s)] | length' "$NORMALISED")
  echo "  ${SRC}: $N" >&2
done
echo "  Output: ${ARCHIVE_DIR}/feed.json" >&2

# The reading view serves data/feed.md at "/" and archived days at "/<date>".
if [[ "$DATE" == "$(date +%Y-%m-%d)" ]]; then
  echo "  View: http://localhost:${PORT:-3000}" >&2
else
  echo "  View: http://localhost:${PORT:-3000}/${DATE}" >&2
fi
