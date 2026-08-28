#!/bin/bash
# Stop hook — logs completion timestamp after every Claude Code session

LOGFILE="data/runs.log"
mkdir -p data
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session completed" >> "$LOGFILE"
exit 0
