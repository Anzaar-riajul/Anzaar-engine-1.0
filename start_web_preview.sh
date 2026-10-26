#!/usr/bin/env bash
# Start Techuboard Multi-Device Web Studio on localhost:8080
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8080
URL="http://localhost:${PORT}"

echo "Starting Techuboard Multi-Device Web Studio on ${URL}..."

# Open browser if on macOS
if command -v open >/dev/null 2>&1; then
    (sleep 1 && open "${URL}") &
fi

python3 "${REPO_ROOT}/web_preview/server.py"
