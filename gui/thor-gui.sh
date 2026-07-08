#!/usr/bin/env bash
# Lightweight Thor GUI using YAD or Zenity.
# shellcheck shell=bash

set -Eeuo pipefail
IFS=$'\n\t'
THOR_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
export GTK_THEME="${GTK_THEME:-Adwaita:dark}"

ui_tool() {
  if command -v yad >/dev/null 2>&1; then printf 'yad'; elif command -v zenity >/dev/null 2>&1; then printf 'zenity'; else return 1; fi
}

show_error() {
  local msg="$1" tool
  tool="$(ui_tool || true)"
  if [[ "$tool" == "yad" ]]; then yad --error --title="Thor" --text="$msg"; elif [[ "$tool" == "zenity" ]]; then zenity --error --title="Thor" --text="$msg"; else printf '%s\n' "$msg" >&2; fi
}

choose_scan() {
  local tool domain logfile pid
  tool="$(ui_tool)" || { printf 'Install zenity or yad for GUI mode.\n' >&2; exit 1; }
  if [[ "$tool" == "yad" ]]; then
    domain="$(yad --entry --title="Thor" --text="Authorized target domain:" --width=480)" || return 0
  else
    domain="$(zenity --entry --title="Thor" --text="Authorized target domain:" --width=480)" || return 0
  fi
  [[ -n "$domain" ]] || return 0
  logfile="$(mktemp /tmp/thor-gui.XXXXXX.log)"
  (THOR_ASSUME_AUTHORIZED=true "$THOR_ROOT/thor.sh" scan "$domain" --authorized --verbose >"$logfile" 2>&1) &
  pid="$!"
  if [[ "$tool" == "yad" ]]; then
    yad --text-info --title="Thor Live Console" --tail --filename="$logfile" --width=980 --height=640 --button="Stop Scan:1" --button="Open Results Folder:2" --button="Close:0"
    case "$?" in
      1) kill -INT "$pid" 2>/dev/null || true ;;
      2) xdg-open "$THOR_ROOT/results" >/dev/null 2>&1 || true ;;
      *) ;;
    esac
  else
    if zenity --text-info --title="Thor Live Console" --filename="$logfile" --width=980 --height=640 --checkbox="Stop scan when closing"; then
      :
    else
      :
    fi
  fi
}

open_results() {
  local latest
  latest="$($THOR_ROOT/thor.sh history | head -n 1 | awk '{for (i=3;i<=NF;i++) printf $i (i<NF?OFS:ORS)}')"
  [[ -n "$latest" && -d "$latest" ]] && xdg-open "$latest" >/dev/null 2>&1 || show_error "No results folder found."
}

export_report() {
  local latest dest
  latest="$($THOR_ROOT/thor.sh history | head -n 1 | awk '{for (i=3;i<=NF;i++) printf $i (i<NF?OFS:ORS)}')"
  [[ -n "$latest" && -f "$latest/report.html" ]] || { show_error "No HTML report found."; return 0; }
  if command -v yad >/dev/null 2>&1; then
    dest="$(yad --file-selection --save --filename="thor-report.html")" || return 0
  else
    dest="$(zenity --file-selection --save --filename="thor-report.html")" || return 0
  fi
  cp "$latest/report.html" "$dest"
}

main_menu() {
  local tool choice
  tool="$(ui_tool)" || { printf 'Install zenity or yad for GUI mode.\n' >&2; exit 1; }
  while true; do
    if [[ "$tool" == "yad" ]]; then
      choice="$(yad --list --title="Thor GUI" --width=520 --height=420 --column Action \
        "Start Scan" "Stop Scan" "Live Console" "Statistics" "Open Results Folder" "Export Report" "Dependency Check" "Settings" "Exit")" || exit 0
    else
      choice="$(zenity --list --title="Thor GUI" --width=520 --height=420 --column Action \
        "Start Scan" "Stop Scan" "Live Console" "Statistics" "Open Results Folder" "Export Report" "Dependency Check" "Settings" "Exit")" || exit 0
    fi
    case "$choice" in
      "Start Scan") choose_scan ;;
      "Stop Scan") pkill -INT -f "$THOR_ROOT/thor.sh scan" || true ;;
      "Live Console") xdg-open "$THOR_ROOT/logs/thor.log" >/dev/null 2>&1 || true ;;
      "Statistics") "$THOR_ROOT/thor.sh" history | { if [[ "$tool" == "yad" ]]; then yad --text-info --title="Thor History" --width=800 --height=400; else zenity --text-info --title="Thor History" --width=800 --height=400; fi; } ;;
      "Open Results Folder") open_results ;;
      "Export Report") export_report ;;
      "Dependency Check") "$THOR_ROOT/thor.sh" doctor | { if [[ "$tool" == "yad" ]]; then yad --text-info --title="Dependency Check" --width=700 --height=500; else zenity --text-info --title="Dependency Check" --width=700 --height=500; fi; } ;;
      "Settings") xdg-open "$THOR_ROOT/config.conf" >/dev/null 2>&1 || ${EDITOR:-nano} "$THOR_ROOT/config.conf" ;;
      "Exit") exit 0 ;;
    esac
  done
}

main_menu
