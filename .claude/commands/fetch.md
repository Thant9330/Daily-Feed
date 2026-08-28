# /fetch

Trigger the data fetch pipeline for all three sources.

Invoke the `fetcher` subagent to run `scripts/run-all.sh` and collect today's raw data
from GitHub Trending, Hacker News, and Reddit into `data/`.

Report back: items collected per source, any failures.
