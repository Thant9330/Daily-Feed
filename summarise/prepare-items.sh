#!/bin/bash
set -euo pipefail

# Gather the day's raw items into a single paste-ready prompt file.
# This script NEVER calls an LLM — it is the shell half before the manual gap:
#   prepare-items.sh  →  data/<date>/prompt.txt  →  (you paste it into a chat)
# Usage: bash prepare-items.sh [data_dir] [date]

DATA_DIR="${1:-data}"
DATE="${2:-$(date +%Y-%m-%d)}"
OUT_DIR="${DATA_DIR}/${DATE}"
PROMPT_FILE="${OUT_DIR}/prompt.txt"

mkdir -p "$OUT_DIR"

# ── Verify input files exist ──────────────────────────────────────────────────
for SRC in github hackernews reddit; do
  FILE="${DATA_DIR}/${SRC}.json"
  if [[ ! -f "$FILE" ]]; then
    echo "WARNING: ${FILE} not found, skipping ${SRC}" >&2
    echo "[]" > "$FILE"
  fi
done

# ── Build item list using jq — process each file separately ──────────────────
# Use jq on each file independently to avoid multi-input issues
GITHUB_LINES=$(jq -r '.[] | [
  "github",
  (.title // ""),
  (.url // ""),
  (.description // "")
] | @tsv' "${DATA_DIR}/github.json" 2>/dev/null || echo "")

HN_LINES=$(jq -r '.[] | [
  "hackernews",
  (.title // ""),
  (.url // ""),
  ""
] | @tsv' "${DATA_DIR}/hackernews.json" 2>/dev/null || echo "")

REDDIT_LINES=$(jq -r '.[] | [
  "reddit",
  (.title // ""),
  (.url // ""),
  ""
] | @tsv' "${DATA_DIR}/reddit.json" 2>/dev/null || echo "")

# Combine lines — skip blank lines. The TSV stays in memory; no side files.
ITEMS_TSV=$(printf '%s\n%s\n%s' "$GITHUB_LINES" "$HN_LINES" "$REDDIT_LINES" | grep -v '^[[:space:]]*$' || true)

ITEM_COUNT=$(echo "$ITEMS_TSV" | grep -c $'\t' 2>/dev/null || echo 0)

if [[ "$ITEM_COUNT" -eq 0 ]]; then
  echo "ERROR: No items found in ${DATA_DIR} — run scripts/run-all.sh first" >&2
  exit 1
fi

# ── Write the prompt ──────────────────────────────────────────────────────────
cat > "$PROMPT_FILE" << 'PROMPT_HEADER'
You are a technical news summariser. For each item below, produce a JSON object.
Return ONLY a valid JSON array — no markdown, no explanation, no code fences.

Each object must have exactly these fields:
{
  "id": "source-slug (lowercase, hyphens, e.g. github-rust-lang-rust)",
  "source": "github|hackernews|reddit",
  "title": "clear descriptive title (keep original if already good)",
  "url": "original url unchanged",
  "summary": "2-3 sentence factual explanation a colleague could repeat without visiting the link",
  "tags": ["pick 1-3 from: AI, ML, tools, web, security, systems, data, mobile, career, other"],
  "relevance": 4,
  "read": false,
  "bookmarked": false
}

Rules:
- Neutral, factual tone — no hype, no superlatives
- Summary must be self-contained
- relevance is 1-5 integer: 5=high technical depth + high community interest, 1=low
- tags: only from the allowed list above

Items to summarise:
PROMPT_HEADER

LINE_NUM=0
while IFS=$'\t' read -r source title url desc; do
  LINE_NUM=$((LINE_NUM + 1))
  printf "\n%d. [%s] %s\n   URL: %s\n" "$LINE_NUM" "$source" "$title" "$url" >> "$PROMPT_FILE"
  if [[ -n "$desc" ]]; then
    printf "   Description: %s\n" "$desc" >> "$PROMPT_FILE"
  fi
done <<< "$ITEMS_TSV"

echo "" >> "$PROMPT_FILE"
echo "Return only the JSON array." >> "$PROMPT_FILE"

# ── Report ────────────────────────────────────────────────────────────────────
echo "=== Prepared ${ITEM_COUNT} items for ${DATE} ===" >&2
for SRC in github hackernews reddit; do
  N=$(echo "$ITEMS_TSV" | grep -c "^${SRC}"$'\t' || true)
  echo "  ${SRC}: ${N}" >&2
done
echo "  Output: $(cd "$OUT_DIR" && pwd)/prompt.txt" >&2
