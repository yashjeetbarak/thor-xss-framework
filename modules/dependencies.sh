#!/usr/bin/env bash
# Dependency checking and optional installer.
# shellcheck shell=bash

set -Eeuo pipefail
IFS=$'\n\t'

missing_deps=()
optional_missing=()

dep_present() {
  local dep="$1"
  case "$dep" in
    httpx) command_exists httpx || command_exists httpx-toolkit ;;
    *) command_exists "$dep" ;;
  esac
}

check_dependencies() {
  missing_deps=()
  optional_missing=()
  local required=(git curl wget grep sed awk jq subfinder sublist3r paramspider dalfox)
  local optional=(httpx gau katana waymore)
  local dep
  printf 'Thor Dependency Check\n=====================\n'
  for dep in "${required[@]}"; do
    if dep_present "$dep"; then printf '  [OK]       %s\n' "$dep"; else printf '  [MISSING]  %s\n' "$dep"; missing_deps+=("$dep"); fi
  done
  for dep in "${optional[@]}"; do
    if dep_present "$dep"; then printf '  [OK/OPT]   %s\n' "$dep"; else printf '  [OPT MISS] %s\n' "$dep"; optional_missing+=("$dep"); fi
  done
  printf '\nRequired missing: %s\nOptional missing: %s\n' "${#missing_deps[@]}" "${#optional_missing[@]}"
  ((${#missing_deps[@]} == 0))
}

ensure_go_path() {
  local gopath gobin
  gopath="$(go env GOPATH 2>/dev/null || printf '%s/go' "$HOME")"
  gobin="$gopath/bin"
  mkdir -p "$gobin"
  case ":$PATH:" in
    *":$gobin:"*) ;;
    *) warn "Add Go binaries to PATH: export PATH=\"\$PATH:$gobin\"" ;;
  esac
}

install_base_packages() {
  local sudo_cmd=()
  [[ "${EUID}" -eq 0 ]] || sudo_cmd=(sudo)
  "${sudo_cmd[@]}" apt-get update
  "${sudo_cmd[@]}" apt-get install -y git curl wget jq golang-go python3 python3-pip pipx zenity yad xdg-utils shellcheck shfmt
  python3 -m pipx ensurepath || true
}

install_tool_go() {
  local name="$1" pkg="$2"
  if dep_present "$name"; then return 0; fi
  info "Installing $name with go install"
  if ! go install "$pkg" >>"$LOG_FILE" 2>&1; then warn "Failed to install $name with go install."; fi
}

install_tool_pipx() {
  local name="$1" pkg="$2"
  if dep_present "$name"; then return 0; fi
  info "Installing $name with pipx"
  if ! pipx install "$pkg" >>"$LOG_FILE" 2>&1; then pipx upgrade "$pkg" >>"$LOG_FILE" 2>&1 || warn "Failed to install $name with pipx."; fi
}

install_missing_dependencies() {
  log_init
  install_base_packages
  ensure_go_path
  install_tool_go subfinder github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
  install_tool_go httpx github.com/projectdiscovery/httpx/cmd/httpx@latest
  install_tool_go katana github.com/projectdiscovery/katana/cmd/katana@latest
  install_tool_go gau github.com/lc/gau/v2/cmd/gau@latest
  install_tool_go dalfox github.com/hahwul/dalfox/v2@latest
  install_tool_pipx sublist3r sublist3r
  install_tool_pipx waymore waymore
  install_tool_pipx paramspider git+https://github.com/devanshbatham/ParamSpider.git
  check_dependencies || true
}

update_tools() { install_missing_dependencies; }
