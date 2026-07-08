#!/usr/bin/env bash
# Remove Thor command wrappers. Results are preserved unless explicitly deleted.
# shellcheck shell=bash

set -Eeuo pipefail
SUDO_CMD=()
[[ "${EUID}" -eq 0 ]] || SUDO_CMD=(sudo)
"${SUDO_CMD[@]}" rm -f /usr/local/bin/thor /usr/local/bin/thor-gui
printf 'Thor command wrappers removed. Project files and results are preserved.\n'
