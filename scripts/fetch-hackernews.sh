#!/bin/bash
set -euo pipefail

# Fetch Hacker News top stories via Algolia API
# Usage: bash fetch-hackernews.sh <output_dir> [since_ts] [until_ts]

OUTPUT_DIR="${1:-data}"
SINCE_TS="${2:-$(date -d '24 hours ago' +%s 2>/dev/null || date -v-24H +%s)}"
UNTIL_TS="${3:-$(date +%s)}"

mkdir -p "$OUTPUT_DIR"

API_URL="https://hn.algolia.com/api/v1/search"

echo "Fetching Hacker News top stories..." >&2
# Use %3E / %3C for > / < — required for Algolia to accept the URL correctly
RESPONSE=$(curl -fsSL --max-time 30 \
  "${API_URL}?tags=front_page&numericFilters=created_at_i%3E${SINCE_TS},created_at_i%3C${UNTIL_TS}&hitsPerPage=30")

# Parse with jq: extract relevant fields
ITEMS_JSON=$(echo "$RESPONSE" | jq '[
  .hits[] |
  select(.title != null and .title != "") |
  {
    id: (.objectID // "hn-\(.story_id // "unknown")"),
    title: .title,
    url: (if .url != null and .url != "" then .url else "https://news.ycombinator.com/item?id=\(.objectID)" end),
    points: (.points // 0),
    num_comments: (.num_comments // 0),
    author: (.author // ""),
    published_at: (.created_at // ""),
    published_ts: (.created_at_i // 0),
    source: "hackernews"
  }
]')

if [[ -z "$ITEMS_JSON" ]] || [[ "$ITEMS_JSON" == "null" ]]; then
  ITEMS_JSON="[]"
fi

echo "$ITEMS_JSON" > "${OUTPUT_DIR}/hackernews.json"

COUNT=$(echo "$ITEMS_JSON" | jq 'length')
echo "HackerNews: $COUNT items written to ${OUTPUT_DIR}/hackernews.json" >&2
