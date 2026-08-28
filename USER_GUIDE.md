# Daily Feed — User Guide

A local technical news aggregator that fetches GitHub Trending, Hacker News, and Reddit every morning, prepares them for summarising, and serves it at `http://localhost:3000` — a clean reading view, with a card dashboard at `/dashboard`.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [First-Time Setup](#2-first-time-setup)
3. [Daily Workflow](#3-daily-workflow)
4. [The Dashboard](#4-the-dashboard)
5. [Running the Pipeline Manually](#5-running-the-pipeline-manually)
6. [Slash Commands (Claude Code)](#6-slash-commands-claude-code)
7. [File Layout](#7-file-layout)
8. [Adding a New Source](#8-adding-a-new-source)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites

| Tool | Purpose | How to install |
|------|---------|----------------|
| **bash** + **curl** | Fetching data | Included in Git Bash / macOS / Linux |
| **jq** | JSON parsing in scripts | `winget install jqlang.jq` (Windows) · `brew install jq` (Mac) · `apt install jq` (Linux) |
| **Node.js v18+** | Dashboard server | https://nodejs.org |
| **Claude Code CLI** | Slash commands (optional) | Already installed if you.re reading this |

> **No API key and no CLI call needed.** The pipeline never talks to an LLM. `prepare-items.sh`
> writes a paste-ready `data/YYYY-MM-DD/prompt.txt`; you paste it into whichever chat you like and
> save the JSON array back as `items.json`; `build-feed.sh` turns that into the feed.

### Make jq available in Git Bash (Windows one-time step)

After installing via winget, copy the binary to your home bin:

```bash
mkdir -p ~/bin
cp "/c/Users/$USERNAME/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe/jq.exe" ~/bin/jq
```

Then add to `~/.bashrc` so it persists across sessions:

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 2. First-Time Setup

```bash
# 1. Enter the project directory
cd path/to/daily-feed

# 2. Install the dashboard server dependency (one time only)
cd web && npm install && cd ..
```

That's it. No `.env` file, no API keys, no database.

---

## 3. Daily Workflow

### The one command

```bash
bash start.sh
```

Installs anything missing, starts the server, fetches all three sources, and builds a
**provisional feed** — today's titles and links with each source's own metadata. Open
**http://localhost:3000** and it's there. No LLM, no API key, no paste required.

### Adding summaries (optional)

The provisional feed has links but no real summaries. To get those:

1. Open `data/YYYY-MM-DD/prompt.txt` and paste the whole thing into a chat
2. Save the JSON array it returns to `data/YYYY-MM-DD/items.json`
3. ```bash
   bash summarise/build-feed.sh data/YYYY-MM-DD/items.json
   ```

Reload the page — the "not summarised yet" banner is gone and every item has a real summary,
tags, and a relevance score. Running `start.sh` again will **not** overwrite them.

### Or run the steps yourself

```bash
bash scripts/run-all.sh          # fetch raw data into data/
bash summarise/prepare-items.sh  # → data/YYYY-MM-DD/prompt.txt (no LLM)
bash summarise/build-raw-feed.sh # → provisional feed.json + feed.md
node web/server.js               # serve at :3000
```

**http://localhost:3000** is the reading view. The card dashboard (filters, search, bookmarks) is
at **http://localhost:3000/dashboard**, and any archived day at
**http://localhost:3000/YYYY-MM-DD**.

---

## 4. The Dashboard

### Header bar
| Element | What it does |
|---------|-------------|
| **▸ Daily Feed** | Brand / home |
| **Date label** | Shows which day's feed is loaded |
| **Search box** | Live filters cards by title and summary text |
| **Date dropdown** | Switch to any archived date |

### Filter bar
| Element | What it does |
|---------|-------------|
| **GitHub / Hacker News / Reddit** chips | Toggle sources on/off. State saved across sessions. |
| **★ Bookmarks** | Show only bookmarked items |
| **Stats** | Live count of visible items · unread · bookmarked |

### Cards

Each card shows:
- **Source chip** (color-coded: indigo = GitHub, orange = HN, teal = Reddit)
- **NEW badge** on items that weren't in yesterday's feed
- **Title link** — click to open the article. The card dims and the title gets a strikethrough to mark it read
- **Summary** — 2–3 sentence explanation written by Claude
- **Tags** — up to 3 topic tags (AI, ML, tools, web, security, systems, data, mobile, career, other)
- **Relevance dot** — grey (low) → blue (medium) → green (high) → amber (top)
- **★ / ☆ bookmark** — click to save. Bookmarks persist in `localStorage`

### Persistence
All read/unread state and bookmarks are saved in the browser's `localStorage` under these keys:

| Key | Stores |
|-----|--------|
| `df_read` | Set of item IDs you've opened |
| `df_bookmarks` | Set of bookmarked item IDs |
| `df_filters` | Which source filters are active |

### Footer actions
| Button | What it does |
|--------|-------------|
| **Mark all read** | Marks every currently-visible item as read |
| **Clear read** | Resets all read state (items become unread again) |

---

## 5. Running the Pipeline Manually

### Fetch one source at a time

```bash
# Arguments: <output_dir> [since_ts] [until_ts]  (timestamps are UNIX seconds)
bash scripts/fetch-github.sh     data/
bash scripts/fetch-hackernews.sh data/
bash scripts/fetch-reddit.sh     data/
```

Raw JSON is written to `data/github.json`, `data/hackernews.json`, `data/reddit.json`.

### Fetch all sources at once

```bash
bash scripts/run-all.sh [output_dir] [since_ts] [until_ts]
# defaults: data/  24h-ago  now
```

Continues even if one source fails. Exits non-zero only if all three fail.

### Summarise (manual — the shell never calls an LLM)

**a. Prepare the prompt**

```bash
bash summarise/prepare-items.sh [data_dir] [date]
# defaults: data/  today
```

Reads the three raw JSON files and writes one paste-ready file:
- `data/YYYY-MM-DD/prompt.txt` — instructions + every item, in a single prompt

**b. Paste it into a chat**

Open `prompt.txt`, paste the whole thing, and save the JSON array that comes back to
`data/YYYY-MM-DD/items.json`. If the reply is wrapped in a ```` ```json ```` fence, delete those
lines first — the scripts do not strip them.

**c. Build the feed**

```bash
bash summarise/build-feed.sh <items_json> [data_dir] [date]
```

Validates the array, enforces the schema with `jq`, and writes:
- `data/feed.json` — structured data for the dashboard
- `data/feed.md` — human-readable grouped by source
- `data/YYYY-MM-DD/` — archived copy of both

`bash summarise/summarise.sh` runs step **a** and then prints these next steps.

### Start the server

```bash
node web/server.js
# or: PORT=8080 node web/server.js
```

Runs on port 3000 by default (`$PORT` env var overrides it).

### API endpoints

| Endpoint | Returns |
|----------|---------|
| `GET /api/feed` | Today's `feed.json` |
| `GET /api/feed/2026-04-06` | Archived feed for that date |
| `GET /api/dates` | `{ dates: ["2026-04-06", ...] }` — all available archive dates |

---

## 6. Slash Commands (Claude Code)

Run these inside the `daily-feed` directory in Claude Code:

| Command | What it does |
|---------|-------------|
| `/refresh` | Full pipeline: fetch → summarise → confirm dashboard ready |
| `/fetch` | Fetch raw data from all three sources only |
| `/summarise` | Summarise whatever is currently in `data/` (skip fetching) |

---

## 7. File Layout

```
daily-feed/
├── CLAUDE.md                   Project rules (read by Claude Code)
├── USER_GUIDE.md               This file
├── scripts/
│   ├── fetch-github.sh         Fetches GitHub Trending RSS
│   ├── fetch-hackernews.sh     Fetches HN front page via Algolia
│   ├── fetch-reddit.sh         Fetches r/programming + r/MachineLearning
│   └── run-all.sh              Runs all three, writes to data/
├── summarise/
│   ├── prepare-items.sh        Writes data/YYYY-MM-DD/prompt.txt (no LLM)
│   ├── build-feed.sh           Reads pasted items.json, writes feed.json + feed.md
│   ├── build-raw-feed.sh       Provisional feed from raw JSON, no summaries
│   └── summarise.sh            Runs prepare-items.sh, prints the manual next steps
├── data/
│   ├── github.json             Raw fetch output
│   ├── hackernews.json
│   ├── reddit.json
│   ├── feed.json               Dashboard reads from this
│   ├── feed.md                 Human-readable summary
│   ├── runs.log                Session completion timestamps
│   └── 2026-04-06/             Archived daily snapshots
│       ├── feed.json
│       └── feed.md
├── web/
│   ├── server.js               Express server (port 3000)
│   ├── package.json
│   └── public/
│       ├── index.html
│       ├── app.js              Vanilla JS dashboard
│       └── style.css
└── .claude/
    ├── agents/
    │   ├── fetcher.md          Fetcher subagent definition
    │   └── summariser.md       Summariser subagent definition
    └── commands/
        ├── fetch.md            /fetch command
        ├── summarise.md        /summarise command
        └── refresh.md          /refresh command
```

**What to back up:** The `data/YYYY-MM-DD/` archive folders contain your full feed history. Everything else can be regenerated.

---

## 8. Adding a New Source

1. Create `scripts/fetch-<source>.sh` following the same interface:
   ```bash
   # $1 = output dir, $2 = since_ts (unix), $3 = until_ts (unix)
   # Write an array of objects to $OUTPUT_DIR/<source>.json
   ```

2. Add it to the `SCRIPTS` array in `scripts/run-all.sh`:
   ```bash
   SCRIPTS=(
     "fetch-github.sh"
     "fetch-hackernews.sh"
     "fetch-reddit.sh"
     "fetch-<source>.sh"   # ← add here
   )
   ```

3. Add a source label to the prompt in `summarise/prepare-items.sh`, and a block to the jq pipeline in `summarise/build-raw-feed.sh`.

4. Add a filter toggle button in `web/public/index.html` and handle it in `app.js`.

Nothing else needs to change.

---

## 9. Troubleshooting

### `jq: command not found`

jq isn't in your PATH. Fix for Git Bash on Windows:

```bash
mkdir -p ~/bin
cp "/c/Users/$USERNAME/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe/jq.exe" ~/bin/jq
export PATH="$HOME/bin:$PATH"   # add to ~/.bashrc to make permanent
```

### `feed.json not found — run /refresh first`

The dashboard has no data yet. Run the full pipeline:

```bash
bash scripts/run-all.sh && bash summarise/summarise.sh
# then paste data/YYYY-MM-DD/prompt.txt into a chat and run:
# bash summarise/build-feed.sh data/YYYY-MM-DD/items.json
```

### One source failed but others succeeded

Check `data/fetch-errors.log` for the timestamp and which script failed. The pipeline is designed to continue — as long as at least one source succeeds, `run-all.sh` exits 0 and prompt preparation proceeds.

Common causes:
- **GitHub RSS** — the RSS host (mshibanami.github.io) is occasionally slow; retry after a minute
- **HackerNews** — Algolia API has a generous rate limit; failures are rare
- **Reddit** — the public JSON API occasionally returns 429; the `sleep 2` between subreddits usually prevents this

### `build-feed.sh` says the file isn't a JSON array

The reply you saved is probably still wrapped in a markdown code fence. Open
`data/YYYY-MM-DD/items.json`, delete the ```` ```json ```` and ```` ``` ```` lines, save, and re-run:

```bash
bash summarise/build-feed.sh data/YYYY-MM-DD/items.json
```

Check it first with `jq -r 'type' data/YYYY-MM-DD/items.json` — it must print `array`.
The raw fetch data is unchanged, so you never need to re-fetch.

### Port 3000 already in use

```bash
PORT=8080 node web/server.js
```

Or kill the existing process:

```bash
# Windows Git Bash
netstat -ano | grep :3000
taskkill /PID <pid> /F
```
