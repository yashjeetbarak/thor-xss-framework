#!/usr/bin/env bash
# Start the Thor browser workbench without changing the CLI.
set -Eeuo pipefail
IFS=$'\n\t'

UI_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$UI_ROOT"

if ! command -v node >/dev/null 2>&1; then
  printf 'Node.js 18+ is required for Thor Workbench UI.\n' >&2
  printf 'Install on Kali: sudo apt install -y nodejs npm\n' >&2
  exit 1
fi

exec node server.js
