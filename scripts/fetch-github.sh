#!/bin/bash
set -euo pipefail

# Fetch GitHub Trending via mshibanami/GitHubTrendingRSS
# Usage: bash fetch-github.sh <output_dir> [since_ts] [until_ts]

OUTPUT_DIR="${1:-data}"
SINCE_TS="${2:-0}"
UNTIL_TS="${3:-9999999999}"

mkdir -p "$OUTPUT_DIR"

RSS_URL="https://mshibanami.github.io/GitHubTrendingRSS/daily/all.xml"

echo "Fetching GitHub Trending RSS..." >&2
XML=$(curl -fsSL --max-time 30 "$RSS_URL")

# Parse RSS items using awk.
# Structure: each <item> contains <title>, <link>, <description> (HTML-encoded), <pubDate>
# description contains HTML entities like &lt;p&gt;...&lt;/p&gt;
ITEMS_JSON=$(echo "$XML" | awk '
BEGIN { in_item=0; in_desc=0; title=""; link=""; desc=""; pubdate="" }

# Start of an item
/<item>/ { in_item=1; title=""; link=""; desc=""; pubdate=""; in_desc=0; next }

in_item {
  # Title (plain text)
  if (match($0, /<title>([^<]+)<\/title>/, a)) {
    title = a[1]
  }
  # Link (skip the channel-level link; only get links inside items)
  if (match($0, /^[[:space:]]*<link>([^<]+)<\/link>/, a)) {
    link = a[1]
  }
  # Description: extract first paragraph from HTML-encoded content
  # Format: <description>&lt;p&gt;TEXT&lt;/p&gt;...
  if (!in_desc && match($0, /<description>/, _)) {
    in_desc = 1
    rest = substr($0, RSTART + RLENGTH)
    # Find first &lt;p&gt;...&lt;/p&gt;
    if (match(rest, /&lt;p&gt;([^&]*)&lt;\/p&gt;/, b)) {
      desc = b[1]
      in_desc = 0
    }
  }
  # pubDate
  if (match($0, /<pubDate>([^<]+)<\/pubDate>/, a)) {
    pubdate = a[1]
  }
}

# End of item
/<\/item>/ {
  if (in_item && title != "") {
    printf "%s\t%s\t%s\t%s\n", title, link, desc, pubdate
  }
  in_item=0; in_desc=0
}
' | while IFS=$'\t' read -r title link desc pubdate; do
    # Timestamp filter
    ts=0
    if [[ -n "$pubdate" ]]; then
      ts=$(date -d "$pubdate" +%s 2>/dev/null || echo "0")
    fi
    if [[ "$ts" -eq 0 ]] || { [[ "$ts" -ge "$SINCE_TS" ]] && [[ "$ts" -le "$UNTIL_TS" ]]; }; then
      jq -n \
        --arg title "$title" \
        --arg url "$link" \
        --arg desc "$desc" \
        --arg pubdate "$pubdate" \
        '{title: $title, url: $url, description: $desc, published_at: $pubdate, source: "github"}'
    fi
  done | jq -s '.')

if [[ -z "$ITEMS_JSON" ]] || [[ "$ITEMS_JSON" == "null" ]]; then
  ITEMS_JSON="[]"
fi

echo "$ITEMS_JSON" > "${OUTPUT_DIR}/github.json"

COUNT=$(echo "$ITEMS_JSON" | jq 'length')
echo "GitHub: $COUNT items written to ${OUTPUT_DIR}/github.json" >&2
