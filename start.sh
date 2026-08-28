#!/bin/bash
set -euo pipefail

# Daily Feed — one-command bootstrap
# Installs deps if needed, starts the dashboard, then refreshes today's news.
#
# The dashboard comes up FIRST and serves whatever feed.json already exists.
# Fetching and summarising run afterwards and are non-fatal: a Reddit outage or
# a slow/failed Claude call must never take the dashboard down with it.

cd "$(dirname "$0")"

# Ensure jq is available — handle Git Bash, WSL, and native Linux
export PATH="$HOME/bin:$PATH"
if ! command -v jq &>/dev/null; then
  # WSL / Debian/Ubuntu
  if command -v apt-get &>/dev/null; then
    echo "→ Installing jq via apt-get..."
    sudo apt-get install -y jq
  # macOS
  elif command -v brew &>/dev/null; then
    echo "→ Installing jq via brew..."
    brew install jq
  else
    echo "ERROR: jq not found. Install it first: https://jqlang.github.io/jq/download/"
    exit 1
  fi
fi

# Install Express if not already installed
if [ ! -d web/node_modules ]; then
  echo "→ Installing dependencies..."
  (cd web && npm install)
fi

# ── Start the dashboard first ────────────────────────────────────────────────
echo "→ Starting dashboard at http://localhost:3000"
node web/server.js &
SERVER_PID=$!

# Stop the server when this script is interrupted (Ctrl-C) or exits
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT INT TERM

# Give the server a moment, then confirm it actually bound the port
sleep 2
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "ERROR: dashboard failed to start" >&2
  exit 1
fi
echo "  ✓ dashboard is up"

# ── Refresh data in the background of the running dashboard ──────────────────
echo "→ Fetching news..."
if bash scripts/run-all.sh; then
  echo "  ✓ fetch complete"
else
  echo "  ✗ fetch failed — dashboard still serving previous data" >&2
fi

# Summarisation is manual: the shell prepares the prompt and stops there.
echo "→ Preparing today's items for summarisation..."
if bash summarise/summarise.sh; then
  echo "  ✓ prompt ready"
else
  echo "  ✗ prepare failed — dashboard still serving previous feed.json" >&2
fi

# ── Provisional feed, so the page always shows today ─────────────────────────
# Built straight from the raw JSON — titles, links, and each source's own
# metadata. No LLM. Real summaries overwrite it when you paste them back.
#
# The guard is what protects your work: a feed carrying a "note" field is
# provisional and safe to rebuild; once you have pasted real summaries the
# note is gone and this step leaves the file alone.
TODAY=$(date +%Y-%m-%d)
ARCHIVE="data/${TODAY}/feed.json"
if [[ ! -f "$ARCHIVE" ]] || jq -e '.note' "$ARCHIVE" >/dev/null 2>&1; then
  echo "→ Building provisional feed (titles + links, no summaries)..."
  if bash summarise/build-raw-feed.sh >/dev/null 2>&1; then
    echo "  ✓ provisional feed built — reload the page to see today's items"
  else
    echo "  ✗ provisional feed failed — dashboard still serving previous feed.json" >&2
  fi
else
  echo "  ✓ today's feed is already summarised — leaving it as is"
fi

echo ""
echo "=== Dashboard running at http://localhost:3000 (Ctrl-C to stop) ==="
echo "    Summaries: paste data/${TODAY}/prompt.txt into a chat, save the JSON array"
echo "    to data/${TODAY}/items.json, then:"
echo "      bash summarise/build-feed.sh data/${TODAY}/items.json"

# Hand the terminal back to the server
wait "$SERVER_PID"
