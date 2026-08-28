# How Daily Feed Works — Technical Deep Dive

This document explains every part of the project so you can understand, modify, and repair it yourself.

---

## The Big Picture

```
Internet                    Your machine
─────────                   ─────────────────────────────────────────
GitHub RSS   ──curl──►  fetch-github.sh   ──►  data/github.json
HN Algolia   ──curl──►  fetch-hackernews.sh ──► data/hackernews.json  ──┬─► prepare-items.sh
Reddit JSON  ──curl──►  fetch-reddit.sh   ──►  data/reddit.json       │        │
                                                                       │        ▼
                                                                       │  data/YYYY-MM-DD/prompt.txt
                                                                       │        │
                                                                       │  (you paste it into a chat —
                                                                       │   the shell never calls an LLM)
                                                                       │        │
                                                                       │        ▼
                                                                       │  data/YYYY-MM-DD/items.json
                                                                       │        │
                                                    build-raw-feed.sh ─┘        │
                                                    (titles + links,            │
                                                     no summaries)              │
                                                            └───────┬───────────┘
                                                                    ▼
                                                              build-feed.sh
                                                                    │
                                                                    ▼
                                                              data/feed.json
                                                              data/feed.md
                                                                    │
                                                               server.js
                                                                    │
                                                                    ▼
                                                        browser (port 3000)
```

The pipeline has three stages:
1. **Fetch** — three shell scripts pull raw data from public APIs
2. **Summarise** — one shell script passes everything to Claude, writes `feed.json`
3. **Serve** — a Node.js server reads `feed.json` and serves the dashboard

Each stage is completely independent. You can run them separately, debug them separately, replace any one without touching the others.

---

## Stage 1 — Fetching Data

### How `run-all.sh` works

`run-all.sh` is the orchestrator. It loops over the three fetch scripts and runs them one by one:

```bash
SCRIPTS=("fetch-github.sh" "fetch-hackernews.sh" "fetch-reddit.sh")

for SCRIPT in "${SCRIPTS[@]}"; do
  bash "${SCRIPT_DIR}/${SCRIPT}" "$OUTPUT_DIR" "$SINCE_TS" "$UNTIL_TS"
done
```

Every fetch script receives the same three arguments:
- `$1` — output directory (default: `data/`)
- `$2` — "since" timestamp in UNIX seconds (default: 24 hours ago)
- `$3` — "until" timestamp in UNIX seconds (default: now)

If one script fails, the others still run. `run-all.sh` only exits with an error if **all three** fail.

---

### fetch-hackernews.sh — the simplest one

Hacker News provides a clean JSON API via Algolia (a search company that indexes HN):

```
https://hn.algolia.com/api/v1/search?tags=front_page&numericFilters=created_at_i>TIMESTAMP&hitsPerPage=30
```

- `tags=front_page` — only stories that made the HN front page
- `numericFilters=created_at_i>SINCE_TS` — only stories posted after our timestamp
- `hitsPerPage=30` — up to 30 results

The response is JSON like this:
```json
{
  "hits": [
    {
      "objectID": "12345",
      "title": "Some article",
      "url": "https://example.com",
      "points": 342,
      "num_comments": 87,
      "author": "someone",
      "created_at": "2026-04-06T08:00:00Z",
      "created_at_i": 1743926400
    }
  ]
}
```

We use `jq` to extract just the fields we need:
```bash
jq '[.hits[] | select(.title != null) | {id, title, url, points, ...}]'
```

`select(.title != null)` skips any malformed entries. The result is written to `data/hackernews.json`.

**No authentication needed** — the Algolia HN API is completely public.

---

### fetch-github.sh — RSS + XML parsing

GitHub itself doesn't offer a trending API. A third-party project called **mshibanami/GitHubTrendingRSS** scrapes GitHub Trending daily and publishes the results as an RSS feed hosted on GitHub Pages:

```
https://mshibanami.github.io/GitHubTrendingRSS/daily/all.xml
```

This returns XML (RSS format), not JSON. Since CLAUDE.md says "no Python in shell scripts" and `xmllint` isn't always available, we parse the XML using `awk` — a text-processing tool that's always present on Unix systems.

**The challenge:** RSS items look like this:
```xml
<item>
  <title>google-ai-edge/gallery</title>
  <link>https://github.com/google-ai-edge/gallery</link>
  <description>&lt;p&gt;A gallery that showcases on-device ML/GenAI use cases.&lt;/p&gt;&lt;hr&gt;...</description>
  <pubDate>Mon, 06 Apr 2026 00:00:00 +0000</pubDate>
</item>
```

Notice the `<description>` uses HTML entities (`&lt;p&gt;` instead of `<p>`). The whole README is encoded in there. We only want the first paragraph.

**How the awk parser works:**

```awk
/<item>/  { in_item=1; reset all variables }

in_item {
  extract title from <title>...</title>
  extract link from <link>...</link>
  extract first &lt;p&gt;...&lt;/p&gt; from <description>
  extract pubDate
}

/<\/item>/ { print title, link, desc, pubdate as tab-separated; in_item=0 }
```

`awk` reads the XML line by line. When it sees `<item>` it sets a flag `in_item=1`. While inside an item, it uses regex to match and extract each field. When it sees `</item>` it outputs the collected data.

After awk extracts the tab-separated lines, a `while read` loop processes each one, builds a JSON object using `jq -n`, and pipes all objects into `jq -s '.'` to assemble the final array.

**Why awk and not grep/sed?**
Grep works on one line at a time and can't track state (like "are we inside an `<item>` block?"). `awk` can maintain state across lines, which makes it suitable for simple XML parsing.

---

### fetch-reddit.sh — the "no API key" question

**Why Reddit works without an API key:**

Reddit has two separate APIs:
1. **OAuth API** (`oauth.reddit.com`) — the official API, requires registration and a key
2. **Public JSON API** (`www.reddit.com`) — a hidden feature where any Reddit URL returns JSON if you add `.json` to it

For example:
- `https://www.reddit.com/r/programming/top` → the normal webpage
- `https://www.reddit.com/r/programming/top.json?t=day&limit=25` → raw JSON of the same page

This JSON endpoint has existed since Reddit's earliest days. Reddit has never shut it down because it powers many legitimate use cases (RSS readers, bots, personal dashboards).

**The catch — User-Agent:**

If you send a request with no User-Agent header (or a generic one like `curl/8.0`), Reddit blocks you with a 429 or 403 error. You must send a descriptive User-Agent:

```bash
curl -A "DailyFeedBot/1.0" "https://www.reddit.com/r/programming/top.json?t=day&limit=25"
```

This is Reddit's way of identifying what's making requests. As long as you're not hammering the API (hence the `sleep 2` between subreddit requests), they let you through.

**What the response looks like:**
```json
{
  "data": {
    "children": [
      {
        "data": {
          "id": "abc123",
          "title": "How Linux executes binaries",
          "url": "https://example.com",
          "score": 1423,
          "num_comments": 89,
          "subreddit": "programming",
          "author": "someone",
          "created_utc": 1743926400.0
        }
      }
    ]
  }
}
```

We use `jq` to navigate this `.data.children[].data` structure and extract the fields we need.

**The two subreddits:**

We fetch both `r/programming` and `r/MachineLearning` in a loop, then merge them:
```bash
ALL_ITEMS=$(echo "$ALL_ITEMS $ITEMS" | jq -s '.[0] + .[1]')
```
`jq -s` (slurp) reads multiple JSON values and puts them in an array. `.[0] + .[1]` concatenates two arrays.

---

## Stage 2 — Summarisation

### The LLM boundary

The pipeline is deliberately split in two. **No shell script here ever calls an LLM** — no
`claude -p`, no API call, no subagent. `prepare-items.sh` gathers, you summarise by hand in a
chat, `build-feed.sh` rebuilds. Everything on either side of the gap is pure shell + `jq`.

### How `prepare-items.sh` works (step by step)

**Step 1 — Read the raw JSON files**

Each source file is processed separately with `jq`:
```bash
GITHUB_LINES=$(jq -r '.[] | ["github", .title, .url, .description] | @tsv' data/github.json)
HN_LINES=$(jq -r '.[] | ["hackernews", .title, .url, ""] | @tsv' data/hackernews.json)
REDDIT_LINES=$(jq -r '.[] | ["reddit", .title, .url, ""] | @tsv' data/reddit.json)
```

`@tsv` (tab-separated values) converts each array to a line like:
```
github	google-ai-edge/gallery	https://github.com/google-ai-edge/gallery	A gallery that showcases...
```

These lines stay in a shell variable — nothing is written to disk except the prompt itself.

**Step 2 — Write the prompt**

A `cat << 'PROMPT_HEADER'` writes the instructions to `data/YYYY-MM-DD/prompt.txt`. Then a
`while read` loop appends each item:

```
1. [github] google-ai-edge/gallery
   URL: https://github.com/google-ai-edge/gallery
   Description: A gallery that showcases on-device ML/GenAI use cases.

2. [hackernews] Eight years of wanting, three months of building with AI
   URL: https://lalitm.com/post/...

...and so on for all 61 items
```

The file is dated, not temporary — it lives alongside that day's archive so you can come back to
it. Re-running the script simply overwrites it.

**Step 3 — You summarise it**

Open `data/YYYY-MM-DD/prompt.txt`, paste the whole thing into a chat, and save the JSON array
that comes back to `data/YYYY-MM-DD/items.json`. All items go in one paste, never one per item.

If the reply arrives wrapped in a markdown code fence (` ```json ... ``` `), delete those lines
before saving. The scripts do not strip them — `build-feed.sh` will tell you the file isn't
valid JSON rather than silently guessing.

### How `build-feed.sh` works (step by step)

**Step 4 — Validate the input**

```bash
jq empty "$ITEMS_JSON"              # is it JSON at all?
jq -r 'type' "$ITEMS_JSON"          # must be "array"
```

If either check fails the script exits with the file path and what it found instead.

**Step 5 — Enforce the schema with jq**

Even with valid JSON, every item is re-shaped through a strict `jq` filter to guarantee all
required fields exist with the right types:

```jq
{
  id: (.id // "fallback-id"),
  source: (.source // "unknown"),
  title: (.title // "Untitled"),
  url: (.url // ""),
  summary: (.summary // ""),
  tags: (if .tags | type == "array" then .tags else [] end),
  relevance: (if .relevance then (.relevance | tonumber | floor) else 3 end),
  read: false,
  bookmarked: false
}
```

The `//` operator in jq means "use this default if the left side is null or missing". This makes
the output bulletproof even if a field was omitted.

**Step 6 — Write output files**

Three things get written:
- `data/feed.json` — the dashboard reads this
- `data/feed.md` — human-readable, grouped by source (assembled by jq)
- `data/YYYY-MM-DD/` — archive copies of both files, next to that day's `prompt.txt`

---

### The provisional feed — `build-raw-feed.sh`

Steps 3 and 4 need you in the loop, which means the page would show stale data until you got
around to pasting. `build-raw-feed.sh` closes that gap without adding an LLM: it reshapes the raw
JSON into the normal feed schema and hands it to `build-feed.sh`, so there is still exactly one
piece of code that knows the feed.json / feed.md / archive layout.

The summary field is whatever each source already told us — never an invention:

| source | provisional summary |
|---|---|
| github | the repo `description` |
| hackernews | `976 points · 292 comments on Hacker News.` |
| reddit | `Posted in r/programming.` |

Reddit shows no counts because `fetch-reddit.sh` writes `score` and `num_comments` as `0` — the
RSS feed does not expose them — so printing "0 points" would claim something untrue about the
post. The jq helper only reports engagement it actually has.

`build-raw-feed.sh` sets `FEED_NOTE`, which makes `build-feed.sh` write two extra things: a `>`
note line under the heading in `feed.md`, and a top-level `note` field in `feed.json`. That field
is the flag `start.sh` reads:

```bash
if [[ ! -f "$ARCHIVE" ]] || jq -e '.note' "$ARCHIVE" >/dev/null 2>&1; then
  bash summarise/build-raw-feed.sh
fi
```

A feed with a `note` is provisional and safe to rebuild. Once you paste real summaries the note is
gone, and every later `start.sh` leaves your work alone.

The reading view also puts `is-provisional` on the article when a note is present, which hides the
tag/relevance row — a provisional item carries `build-feed.sh`'s default relevance of 3, and
showing that would imply a judgement nobody made.

---

## Stage 3 — The Server

### How `server.js` works

It's an Express (Node.js) HTTP server. Pages first, then the API, then static files:

```
GET /                  → web/public/read.html   (reading view — the default page)
GET /dashboard         → web/public/index.html  (the card UI)
GET /YYYY-MM-DD        → web/public/read.html   (reading view for an archived day)
GET /api/feed          → reads data/feed.json and sends it as JSON
GET /api/feed/:date    → reads data/YYYY-MM-DD/feed.json (archive)
GET /api/feed.md       → reads data/feed.md and sends it as text/plain
GET /api/feed.md/:date → reads data/YYYY-MM-DD/feed.md (archive)
GET /api/dates         → scans data/ for YYYY-MM-DD folders, returns the list
```

For static files (read.js, app.js, style.css), Express's built-in `express.static` middleware handles everything automatically — no custom code needed.

Two ordering details matter. `GET /` is registered **before** `express.static`, or the static middleware would serve `index.html` at the root. `GET /:date` is registered **after** it, so real files still win over the date pattern; the date is checked inside the handler with `next()` on a miss, because Express 5 dropped inline path regexes like `/:date(\d{4}-\d{2}-\d{2})`.

`read.js` renders the markdown itself with a small line-based parser matched to the grammar `build-feed.sh` emits — headings, a bare URL line, a summary paragraph, and a `Tags: … | Relevance: n/5` line. It is not a general markdown engine, and it builds DOM nodes with `createElement`/`textContent` rather than `innerHTML`, so model-written titles and summaries can never inject markup.

For the API routes, it uses `res.sendFile()` which streams the file directly to the browser without reading the whole thing into memory first.

The `/api/dates` endpoint scans the `data/` directory for folders matching the pattern `YYYY-MM-DD` and checks each one has a `feed.json` inside. This is how the date dropdown in the dashboard gets populated.

---

## Stage 4 — The Dashboard

### How `app.js` works

The dashboard is vanilla JavaScript — no React, no Vue, no libraries. On page load:

```javascript
init()
  → loadSet('df_read')       // load read IDs from localStorage
  → loadSet('df_bookmarks')  // load bookmark IDs from localStorage
  → loadFilters()            // load active source filters from localStorage
  → populateDatePicker()     // fetch /api/dates, fill the dropdown
  → loadFeed(null)           // fetch /api/feed, render cards
```

**Rendering cards:**

`loadFeed()` fetches `/api/feed`, stores all items in `state.allItems`, then calls `renderAll()`.

`renderAll()` calls `getVisible()` which filters `state.allItems` by:
- Active source filters
- Bookmark-only mode
- Search query

For each visible item, `buildCard()` creates an `<article>` DOM element with the card HTML using template literals (backtick strings). It checks `state.read` and `state.bookmarks` to apply the correct visual state.

**Interactivity without re-rendering:**

When you click a title link, only that card's class changes (`card.classList.add('is-read')`). The full card list is NOT re-rendered — this keeps the UI fast.

Only when you toggle a filter, search, or switch dates does `renderAll()` run again to rebuild the entire card grid.

**localStorage persistence:**

Every read/bookmark change saves a `Set` to localStorage as a JSON array:
```javascript
function saveSet(key, set) {
  localStorage.setItem(key, JSON.stringify([...set]));
}
```

On next load, it's restored:
```javascript
function loadSet(key) {
  return new Set(JSON.parse(localStorage.getItem(key) || '[]'));
}
```

---

## How to Modify Things

### Change which subreddits are fetched
Edit `scripts/fetch-reddit.sh`, line 14:
```bash
SUBREDDITS=("programming" "MachineLearning")
# change to whatever you want, e.g.:
SUBREDDITS=("programming" "MachineLearning" "devops" "golang")
```

### Change how many HN stories are fetched
Edit `scripts/fetch-hackernews.sh`, line 17:
```
hitsPerPage=30   ← change this number
```

### Change the summariser prompt / instructions
Edit `summarise/prepare-items.sh`, the block between `cat > "$PROMPT_FILE" << 'PROMPT_HEADER'` and `PROMPT_HEADER`. This is what ends up at the top of `prompt.txt`. Change the tone, add/remove tags, adjust the summary length, etc.

### Change the model
There is no model to change — the pipeline never calls one. Paste `prompt.txt` into whichever chat or model you prefer.

### Add a new source
1. Create `scripts/fetch-NEWSOURCE.sh` — it must write a JSON array to `$OUTPUT_DIR/NEWSOURCE.json`
2. Add `"fetch-NEWSOURCE.sh"` to the `SCRIPTS` array in `scripts/run-all.sh`
3. Add a `NEWSOURCE_LINES=$(jq ... data/NEWSOURCE.json)` block in `summarise/prepare-items.sh` and include it in the `ITEMS_TSV` line
4. Add a filter toggle button in `web/public/index.html`
5. Handle the new source colour in `web/public/style.css`

### Change the dashboard port
```bash
PORT=8080 node web/server.js
```
Or edit `web/server.js` line 5:
```javascript
const PORT = process.env.PORT || 3000;  ← change 3000
```

---

## How to Debug

### "Which items did the fetch return?"
```bash
export PATH="$HOME/bin:$PATH"
jq 'length' data/hackernews.json   # how many items?
jq '.[0]' data/hackernews.json     # inspect first item
```

### "What prompt am I pasting?"
```bash
cat data/$(date +%Y-%m-%d)/prompt.txt
```
It's a plain text file — open it in any editor.

### "Is the array I pasted back usable?"
```bash
jq -r 'type, length' data/$(date +%Y-%m-%d)/items.json   # want: array, then the item count
```
If that errors, the reply probably still has a ```` ```json ```` fence around it — remove those lines.

### "Is feed.json valid?"
```bash
jq empty data/feed.json && echo "valid" || echo "BROKEN"
```

### "Why is the dashboard blank?"
Open browser DevTools (F12) → Console tab. The app prints errors there if the API fails.
