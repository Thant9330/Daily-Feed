# Daily Feed — Project Constitution

## What this project does
Fetches technical news from 3 sources every morning, summarises with Claude (Haiku),
and serves a dashboard UI. No email. No login. Just a clean daily feed.

## Sources
- GitHub Trending — via mshibanami/GitHubTrendingRSS (no auth)
- Hacker News   — via Algolia API (no auth)
- Reddit        — r/programming + r/MachineLearning via public Atom feed (User-Agent required)

## Folder layout
```
daily-feed/
├── CLAUDE.md                  ← you are here
├── scripts/
│   ├── fetch-github.sh        ← fetch GitHub Trending RSS
│   ├── fetch-hackernews.sh    ← fetch HN top stories past 24h
│   ├── fetch-reddit.sh        ← fetch Reddit top posts (day)
│   └── run-all.sh             ← calls all 3, writes to data/
├── summarise/
│   ├── prepare-items.sh       ← reads data/, writes data/YYYY-MM-DD/prompt.txt (no LLM)
│   ├── build-feed.sh          ← reads pasted items.json, writes feed.json + feed.md
│   ├── build-raw-feed.sh      ← provisional feed from raw JSON, no summaries (no LLM)
│   └── summarise.sh           ← runs prepare-items.sh, then prints the manual next steps
├── data/
│   ├── github.json
│   ├── hackernews.json
│   ├── reddit.json
│   └── YYYY-MM-DD/            ← archived daily snapshots
├── web/
│   ├── server.js              ← lightweight Node server (Express)
│   └── public/
│       ├── read.html          ← reading view (rendered feed.md) — the default page
│       ├── read.js / read.css
│       ├── index.html         ← card dashboard, served at /dashboard
│       ├── app.js
│       └── style.css
└── .claude/
    ├── agents/
    │   ├── fetcher.md
    │   └── summariser.md
    └── commands/
        ├── fetch.md
        ├── summarise.md
        └── refresh.md
```

## Key rules — always follow these
- Shell scripts use `#!/bin/bash` and `set -euo pipefail`
- All scripts accept `$1=output_dir $2=since_ts $3=until_ts` as UNIX timestamps
- Raw data always written as JSON to `data/<source>.json`
- Never hardcode API keys. Use env vars: `ANTHROPIC_API_KEY`
- Use `jq` for all JSON parsing — no Python/Node in shell scripts
- Reddit requests must include `User-Agent: DailyFeedBot/1.0`. Fetch ALL subreddits in ONE
  combined `r/a+b` request — the feed rate-limits hard (429) on back-to-back calls, so a second
  request costs more than it gains. Failures retry 3× with a 15s/30s backoff; adding a subreddit
  to the `SUBREDDITS` array costs no extra request. The Atom feed carries no score or comment
  count, so both are written as 0.
- Qiita/Zenn date quirks: see scripts for inline comments
- The web UI reads only `build-feed.sh` outputs — `data/feed.json` (dashboard) and
  `data/feed.md` (reading view) — never the raw `github.json`/`hackernews.json`/`reddit.json`
- `feed.json` schema: `{ date, items: [{ id, source, title, url, summary, tags, relevance, read, bookmarked }] }`
- Optional top-level `note` on `feed.json` marks a PROVISIONAL feed (built by `build-raw-feed.sh`
  from raw data, no summaries). Its presence means the feed is safe to overwrite; real summaries
  leave it unset. `start.sh` uses exactly this to avoid clobbering your work.

## Extensibility rule
To add a new source later:
1. drop a new `fetch-<source>.sh` in `scripts/` and add one line to `run-all.sh`
2. add a `<source>_LINES` jq block in `summarise/prepare-items.sh`, plus the source name on the
   schema line in its prompt heredoc
3. add a block to the jq pipeline in `summarise/build-raw-feed.sh`
4. add a filter toggle in `web/public/index.html` and a `.src-<source>` colour in `read.css`

Nothing else changes.

## Summarisation model — MANUAL, split at the LLM boundary
- The shell NEVER calls an LLM: no `claude -p`, no API call, no subagent
- `prepare-items.sh` gathers the day's items into ONE paste-ready `data/YYYY-MM-DD/prompt.txt`
- You paste that into a chat and save the JSON array to `data/YYYY-MM-DD/items.json`
- `build-feed.sh` turns it into `feed.json` + `feed.md` with pure jq
- Cost in the pipeline is zero; all items go in one paste, never one per item
- `start.sh` builds a provisional feed from raw data so the page always shows today; pasting
  summaries overwrites it

## Web UI
`localhost:3000` is the reading view: `data/feed.md` rendered top to bottom, with a date picker
and a link to the dashboard. Archived days at `localhost:3000/YYYY-MM-DD`.
`localhost:3000/dashboard` is the card UI.

### Dashboard must-haves
- Source filter: GitHub / HN / Reddit toggles
- Read/unread tracking (persisted in localStorage)
- Bookmark toggle per item
- Search bar (client-side, filters by title + summary)
- "New since yesterday" badge
- Date picker to browse archive

## What NOT to do
- Do not add email delivery (not in scope)
- Do not add authentication
- Do not use a database — flat JSON files are sufficient
- Do not install heavy frameworks — vanilla JS or minimal dependencies only
