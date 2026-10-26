#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Techuboard"

echo "=== 1/3: Closing active Techuboard ==="
killall "${APP_NAME}" 2>/dev/null || true
for _ in {1..20}; do
  pgrep -x "${APP_NAME}" >/dev/null || break
  sleep 0.1
done

echo "=== 2/3: Compiling & Installing to /Applications ==="
INSTALL_APP=1 LAUNCH_APP=1 "${REPO_ROOT}/build_macos_app.sh"

echo "=== 3/3: Techuboard successfully updated and relaunched! ==="
