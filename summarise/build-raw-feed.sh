#!/bin/bash
set -euo pipefail

# Build a PROVISIONAL feed straight from the raw source JSON — every title and
# link, plus whatever metadata each source already gives. No LLM, no API.
#
# This is what makes `bash start.sh` enough on its own: the page shows today's
# items immediately, and real summaries overwrite this feed when you paste them
# back (see build-feed.sh). All the writing is delegated to build-feed.sh so
# there is exactly one place that knows the feed.json / feed.md / archive layout.
#
# Usage: bash build-raw-feed.sh [data_dir] [date]

DATA_DIR="${1:-data}"
DATE="${2:-$(date +%Y-%m-%d)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${DATA_DIR}/${DATE}"
ITEMS_RAW="${OUT_DIR}/items-raw.json"

mkdir -p "$OUT_DIR"

# ── Verify input files exist ──────────────────────────────────────────────────
for SRC in github hackernews reddit; do
  FILE="${DATA_DIR}/${SRC}.json"
  if [[ ! -f "$FILE" ]]; then
    echo "WARNING: ${FILE} not found, skipping ${SRC}" >&2
    echo "[]" > "$FILE"
  fi
done

# ── Shape each source into the feed schema ───────────────────────────────────
# The summary is the honest metadata each source hands us, not an invention.
jq -n \
  --slurpfile gh "${DATA_DIR}/github.json" \
  --slurpfile hn "${DATA_DIR}/hackernews.json" \
  --slurpfile rd "${DATA_DIR}/reddit.json" '
  def plural($n; $word): "\($n) \($word)\(if $n == 1 then "" else "s" end)";
  # Only report engagement we actually have. fetch-reddit.sh writes score and
  # num_comments as 0 because the RSS feed does not expose them, so printing
  # "0 points" would claim something untrue about the post.
  def engagement($score; $comments):
    [ (if $score > 0 then plural($score; "point") else empty end),
      (if $comments > 0 then plural($comments; "comment") else empty end) ];

  ($gh[0] // []) | map({
    # github items carry no id — slug it from the owner/repo in the url
    id: ("github-" + ((.url // "") | sub("^https?://github\\.com/"; "") | gsub("[^A-Za-z0-9]+"; "-") | ascii_downcase)),
    source: "github",
    title: (.title // "Untitled"),
    url: (.url // ""),
    summary: (if (.description // "") != "" then .description else "Trending on GitHub." end),
    tags: [],
    relevance: 3
  })
  +
  (($hn[0] // []) | map({
    id: ("hackernews-" + (.id // "unknown" | tostring)),
    source: "hackernews",
    title: (.title // "Untitled"),
    url: (.url // ""),
    summary: (engagement(.points // 0; .num_comments // 0)
              | if length == 0 then "Posted on Hacker News." else join(" · ") + " on Hacker News." end),
    tags: [],
    relevance: 3
  }))
  +
  (($rd[0] // []) | map({
    id: (.id // "reddit-unknown" | tostring),
    source: "reddit",
    title: (.title // "Untitled"),
    url: (.url // ""),
    summary: (("r/" + (.subreddit // "unknown")) as $sub
              | engagement(.score // 0; .num_comments // 0)
              | if length == 0 then "Posted in \($sub)." else "\($sub) · " + join(" · ") + "." end),
    tags: [],
    relevance: 3
  }))
' > "$ITEMS_RAW"

COUNT=$(jq 'length' "$ITEMS_RAW")
if [[ "$COUNT" -eq 0 ]]; then
  echo "ERROR: no items in ${DATA_DIR} — run scripts/run-all.sh first" >&2
  rm -f "$ITEMS_RAW"
  exit 1
fi

# ── Hand off to build-feed.sh, flagged as provisional ────────────────────────
export FEED_NOTE="Not summarised yet — ${COUNT} items straight from the sources. Paste ${OUT_DIR}/prompt.txt into a chat for summaries."
bash "${SCRIPT_DIR}/build-feed.sh" "$ITEMS_RAW" "$DATA_DIR" "$DATE"
