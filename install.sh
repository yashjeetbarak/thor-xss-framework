#!/usr/bin/env bash
# Install Thor on Kali Linux or compatible Debian systems.
# shellcheck shell=bash

set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SUDO_CMD=()
[[ "${EUID}" -eq 0 ]] || SUDO_CMD=(sudo)

chmod +x "$ROOT/thor.sh" "$ROOT/update.sh" "$ROOT/uninstall.sh" "$ROOT/gui/thor-gui.sh"
find "$ROOT/modules" -type f -name '*.sh' -exec chmod 0644 {} +
mkdir -p "$ROOT/results" "$ROOT/logs"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/thor.sh" "$ROOT"/*.sh "$ROOT"/gui/*.sh "$ROOT"/modules/**/*.sh || true
fi

"${SUDO_CMD[@]}" tee /usr/local/bin/thor >/dev/null <<EOF
#!/usr/bin/env bash
cd "$ROOT" || exit 1
exec "$ROOT/thor.sh" "\$@"
EOF
"${SUDO_CMD[@]}" tee /usr/local/bin/thor-gui >/dev/null <<EOF
#!/usr/bin/env bash
cd "$ROOT" || exit 1
exec "$ROOT/gui/thor-gui.sh" "\$@"
EOF
"${SUDO_CMD[@]}" chmod +x /usr/local/bin/thor /usr/local/bin/thor-gui

cat <<EOF
Thor installed.

Commands:
  thor --help
  thor doctor
  thor doctor --install
  thor scan example.com
  thor-gui
EOF

read -r -p 'Run dependency installer now? [y/N] ' ans || ans=""
if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then "$ROOT/thor.sh" doctor --install; fi
