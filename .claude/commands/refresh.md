# /refresh

Fetch today's news and prepare it for summarisation. The pipeline stops at the
prompt file — summarising is manual (see /summarise).

Steps:
1. Invoke the `fetcher` subagent (/fetch)
2. If fetch succeeds (at least 2 of 3 sources), run `bash summarise/prepare-items.sh` and stop
3. Confirm `data/YYYY-MM-DD/prompt.txt` is written and non-empty
4. Print a summary: date, items per source, total items, and the prompt.txt path

If fetch fails completely (0 sources), stop and report — do not prepare a prompt.

To finish the feed: paste `prompt.txt` into the chat, save the JSON array to
`data/YYYY-MM-DD/items.json`, then run `bash summarise/build-feed.sh data/YYYY-MM-DD/items.json`.
