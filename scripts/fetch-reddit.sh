#!/bin/bash
set -euo pipefail

# Fetch Reddit top posts via the public Atom feed
# Usage: bash fetch-reddit.sh <output_dir> [since_ts] [until_ts]
#
# Reddit quirk 1: the public JSON API (/top.json) now returns 403 for
# unauthenticated clients regardless of User-Agent. The .rss (Atom) feed is
# still open, so we parse that instead — same approach as fetch-github.sh.
# The feed does not expose score/num_comments, so those are written as 0.
#
# Reddit quirk 2: the feed rate-limits hard (429) on back-to-back requests —
# even several seconds apart. So all subreddits are fetched in ONE request via
# the combined "r/a+b" form, and each item's subreddit is read back from its
# <category term="..."> tag. Adding a subreddit below costs no extra request.

OUTPUT_DIR="${1:-data}"
SINCE_TS="${2:-0}"
UNTIL_TS="${3:-9999999999}"

mkdir -p "$OUTPUT_DIR"

SUBREDDITS=("programming" "MachineLearning")

# Join with "+" → programming+MachineLearning
SUB_PATH=$(printf '%s+' "${SUBREDDITS[@]}")
SUB_PATH="${SUB_PATH%+}"

# Reddit escapes markup into the feed. Decode one level; &amp; goes last so
# that "&amp;lt;" does not collapse two levels in a single pass.
decode_once() {
  sed -e 's/&#32;/ /g' \
      -e "s/&#39;/'/g" \
      -e "s/&apos;/'/g" \
      -e 's/&quot;/"/g' \
      -e 's/&lt;/</g' \
      -e 's/&gt;/>/g' \
      -e 's/&amp;/\&/g'
}

echo "Fetching r/${SUB_PATH}..." >&2

XML=""
for ATTEMPT in 1 2 3; do
  if XML=$(curl -fsSL --max-time 30 \
    -A "DailyFeedBot/1.0" \
    "https://www.reddit.com/r/${SUB_PATH}/top.rss?t=day&limit=50"); then
    break
  fi
  XML=""
  if [[ "$ATTEMPT" -lt 3 ]]; then
    BACKOFF=$((ATTEMPT * 15))
    echo "  request failed, retrying in ${BACKOFF}s..." >&2
    sleep "$BACKOFF"
  fi
done

# Leave the previous reddit.json intact rather than overwriting good data
# with an empty array.
if [[ -z "$XML" ]]; then
  echo "ERROR: Reddit feed unavailable after 3 attempts — keeping previous reddit.json" >&2
  exit 1
fi

# The whole feed arrives as one line — split it so each <entry> is its own
# record, then drop the channel header (everything before the first entry).
ALL_ITEMS=$(printf '%s' "$XML" \
  | sed 's|<entry>|\n<entry>|g' \
  | grep '^<entry>' \
  | while IFS= read -r ENTRY; do
      TITLE=$(printf '%s' "$ENTRY" | sed -n 's|.*<title>\(.*\)</title>.*|\1|p' | decode_once)
      POST_ID=$(printf '%s' "$ENTRY" | sed -n 's|.*<id>t3_\([^<]*\)</id>.*|\1|p')
      PUBLISHED=$(printf '%s' "$ENTRY" | sed -n 's|.*<published>\([^<]*\)</published>.*|\1|p')
      AUTHOR=$(printf '%s' "$ENTRY" | sed -n 's|.*<author><name>/u/\([^<]*\)</name>.*|\1|p')
      PERMALINK=$(printf '%s' "$ENTRY" | sed -n 's|.*<link href="\([^"]*\)".*|\1|p')
      # Which subreddit this post came from (combined feed mixes them)
      SUBREDDIT=$(printf '%s' "$ENTRY" | sed -n 's|.*<category term="\([^"]*\)".*|\1|p')

      # The outbound article URL lives inside <content>, escaped twice:
      # &lt;a href=&quot;URL&quot;&gt;[link]&lt;/a&gt;
      URL=$(printf '%s' "$ENTRY" | decode_once \
            | sed -n 's|.*<a href="\([^"]*\)">\[link\]</a>.*|\1|p' | decode_once)
      [[ -z "$URL" ]] && URL="$PERMALINK"

      [[ -z "$TITLE" ]] && continue

      # Timestamp filter — keep the item if the date cannot be parsed
      TS=0
      if [[ -n "$PUBLISHED" ]]; then
        TS=$(date -d "$PUBLISHED" +%s 2>/dev/null || echo "0")
      fi
      if [[ "$TS" -ne 0 ]] && { [[ "$TS" -lt "$SINCE_TS" ]] || [[ "$TS" -gt "$UNTIL_TS" ]]; }; then
        continue
      fi

      jq -n \
        --arg id "reddit-${POST_ID}" \
        --arg title "$TITLE" \
        --arg url "$URL" \
        --arg subreddit "$SUBREDDIT" \
        --arg author "$AUTHOR" \
        --argjson published_ts "$TS" \
        --arg published_at "$PUBLISHED" \
        '{
          id: $id,
          title: $title,
          url: $url,
          score: 0,
          num_comments: 0,
          subreddit: $subreddit,
          author: $author,
          published_ts: $published_ts,
          published_at: $published_at,
          source: "reddit"
        }'
    done | jq -s '.')

if [[ -z "$ALL_ITEMS" ]] || [[ "$ALL_ITEMS" == "null" ]]; then
  ALL_ITEMS="[]"
fi

echo "$ALL_ITEMS" > "${OUTPUT_DIR}/reddit.json"

COUNT=$(echo "$ALL_ITEMS" | jq 'length')
echo "Reddit: $COUNT items written to ${OUTPUT_DIR}/reddit.json" >&2
