#!/bin/zsh
# Pull the latest source and reinstall DevCommand (rebuilds + relaunches).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▶ Pulling latest…"
git pull --ff-only

"$ROOT/scripts/install.sh"
