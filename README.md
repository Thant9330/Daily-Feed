# Daily Feed — Setup & Automation

A local technical news aggregator. Fetches GitHub Trending, Hacker News, and Reddit every morning, summarises with Claude, and serves a dashboard at `http://localhost:3000`.

## Requirements

- bash, curl, jq
- Node.js 18+
- no API key needed

## First run

```bash
bash start.sh
```

That's it. `start.sh` installs dependencies, fetches today's news, summarises with Claude, and starts the server.

## Daily use

```bash
# Full pipeline (fetch + summarise) then open dashboard
bash start.sh

# Or with npm from the project root:
npm run refresh   # fetch + prepare the prompt
npm start         # start server only
```

## Manual steps (if you prefer)

```bash
bash scripts/run-all.sh          # fetch raw data → data/*.json
bash summarise/prepare-items.sh  # → data/YYYY-MM-DD/prompt.txt  (no LLM is called)

# paste prompt.txt into a chat, save the JSON array as data/YYYY-MM-DD/items.json, then:
bash summarise/build-feed.sh data/YYYY-MM-DD/items.json   # → data/feed.json + feed.md

node web/server.js               # serve dashboard at :3000
```

## Claude Code slash commands

```
/refresh     — fetch, then prepare data/YYYY-MM-DD/prompt.txt
/fetch       — fetch only
/summarise   — prepare the prompt from existing raw data
```

## Reading the feed

```bash
bash start.sh          # one command: deps, server, fetch, provisional feed
```

Then open `http://localhost:3000`. You see today's items straight away — titles, links, and each
source's own metadata — with no LLM involved anywhere. Paste `data/YYYY-MM-DD/prompt.txt` into a
chat when you want real summaries; they overwrite the provisional feed.

```
localhost:3000              rendered feed.md (today)
localhost:3000/2026-08-26   any archived day
localhost:3000/dashboard    card UI: filters, search, bookmarks, read tracking
```

## Adding a new source

1. Write `scripts/fetch-<source>.sh` (interface: `$1=dir $2=since_ts $3=until_ts`)
2. Add one line to `SCRIPTS` array in `scripts/run-all.sh`
3. Add source parsing in `summarise/prepare-items.sh` and `summarise/build-raw-feed.sh`
4. Add filter toggle in `web/public/index.html`

See `HOW_IT_WORKS.md` for a full technical walkthrough.
