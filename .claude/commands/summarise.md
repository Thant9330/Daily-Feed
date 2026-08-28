# /summarise

Prepare today's items for manual summarisation. **No LLM is called by the pipeline** —
the shell gathers, you summarise in chat, the shell rebuilds.

## Steps
1. Run `bash summarise/prepare-items.sh` — writes `data/YYYY-MM-DD/prompt.txt`
2. Paste the contents of that file into the chat
3. Save the JSON array it returns to `data/YYYY-MM-DD/items.json`
4. Run `bash summarise/build-feed.sh data/YYYY-MM-DD/items.json` — writes
   `data/feed.json` + `data/feed.md` and archives both to `data/YYYY-MM-DD/`

Report back: items prepared per source and the path of `prompt.txt`.
