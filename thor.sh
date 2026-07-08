#!/usr/bin/env bash
# Thor - The Automated Recon & XSS Hunting Framework
# Educational and authorized security assessment automation only.
# shellcheck shell=bash

set -Eeuo pipefail
IFS=$'\n\t'

THOR_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export THOR_ROOT

# shellcheck disable=SC1091
source "$THOR_ROOT/modules/lib/common.sh"
# shellcheck disable=SC1091
source "$THOR_ROOT/modules/dependencies.sh"
# shellcheck disable=SC1091
source "$THOR_ROOT/modules/reporting.sh"
# shellcheck disable=SC1091
source "$THOR_ROOT/modules/registry.sh"

load_config
load_plugins

confirm_authorized() {
  local target="$1"
  if [[ -t 0 && "${THOR_ASSUME_AUTHORIZED:-false}" != "true" ]]; then
    printf '\nThor must only be used against assets you own or are authorized to assess.\n'
    printf 'Target: %s\n' "$target"
    read -r -p 'Type AUTHORIZED to continue: ' answer
    [[ "$answer" == "AUTHORIZED" ]] || { err "Authorization confirmation failed."; exit 1; }
  fi
}

parse_scan_options() {
  SCAN_DOMAIN=""
  SCAN_LIST=""
  while (($#)); do
    case "$1" in
      -l|--list)
        SCAN_LIST="${2:-}"; shift 2 ;;
      --threads)
        THREADS="${2:-}"; validate_positive_int THREADS; shift 2 ;;
      --httpx-threads)
        HTTPX_THREADS="${2:-}"; validate_positive_int HTTPX_THREADS; shift 2 ;;
      --paramspider-threads)
        PARAMSPIDER_THREADS="${2:-}"; validate_positive_int PARAMSPIDER_THREADS; shift 2 ;;
      --dalfox-workers)
        DALFOX_WORKERS="${2:-}"; validate_positive_int DALFOX_WORKERS; shift 2 ;;
      --dalfox-timeout)
        DALFOX_TIMEOUT="${2:-}"; validate_positive_int DALFOX_TIMEOUT; shift 2 ;;
      --dalfox-delay)
        DALFOX_DELAY="${2:-}"; validate_nonnegative_int DALFOX_DELAY; shift 2 ;;
      --dalfox-retries)
        DALFOX_RETRIES="${2:-}"; validate_positive_int DALFOX_RETRIES; shift 2 ;;
      --dalfox-batch-size)
        DALFOX_BATCH_SIZE="${2:-}"; validate_nonnegative_int DALFOX_BATCH_SIZE; shift 2 ;;
      --dalfox-precheck-live)
        DALFOX_PRECHECK_LIVE="true"; shift ;;
      --no-dalfox-precheck-live)
        DALFOX_PRECHECK_LIVE="false"; shift ;;
      --dalfox-workers-safe)
        DALFOX_WORKERS="25"; DALFOX_BATCH_SIZE="250"; DALFOX_RETRIES="1"; shift ;;
      --dalfox-method)
        DALFOX_REQUEST_METHOD="${2:-}"; shift 2 ;;
      --dalfox-payload-file)
        DALFOX_CUSTOM_PAYLOAD_FILE="${2:-}"; shift 2 ;;
      --dalfox-raw-json)
        DALFOX_SAVE_RAW_JSON="true"; shift ;;
      --dalfox-no-scope-only)
        DALFOX_SCOPE_ONLY="false"; shift ;;
      --no-httpx)
        ENABLE_HTTPX="false"; shift ;;
      --no-gau)
        ENABLE_GAU="false"; shift ;;
      --no-waymore)
        ENABLE_WAYMORE="false"; shift ;;
      --no-katana)
        ENABLE_KATANA="false"; shift ;;
      --proxy)
        PROXY="${2:-}"; shift 2 ;;
      --cookie|--cookies)
        COOKIES="${2:-}"; shift 2 ;;
      --header)
        if [[ -n "$HEADERS" ]]; then HEADERS+=$'\n'; fi
        HEADERS+="${2:-}"; shift 2 ;;
      --user-agent)
        USER_AGENT="${2:-}"; shift 2 ;;
      --verbose)
        VERBOSE="true"; shift ;;
      --debug)
        DEBUG="true"; VERBOSE="true"; shift ;;
      --silent)
        SILENT="true"; shift ;;
      --yes|--authorized)
        THOR_ASSUME_AUTHORIZED="true"; export THOR_ASSUME_AUTHORIZED; shift ;;
      -h|--help)
        usage; exit 0 ;;
      --*)
        err "Unknown scan option: $1"; exit 2 ;;
      *)
        if [[ -z "$SCAN_DOMAIN" ]]; then SCAN_DOMAIN="$1"; else err "Unexpected argument: $1"; exit 2; fi
        shift ;;
    esac
  done
}

scan_one() {
  local raw="$1" domain
  domain="$(normalize_domain "$raw")"
  validate_target_domain "$domain"
  confirm_authorized "$domain"
  init_scan_dir "$domain"
  log_msg INFO "Thor version $THOR_VERSION started for $domain"
  run_pipeline
  generate_reports
  log_msg INFO "Thor scan completed for $domain"
  printf '\nScan complete. Reports:\n  %s\n  %s\n  %s\n' "$SCAN_DIR/report.txt" "$SCAN_DIR/report.json" "$SCAN_DIR/report.html"
}

scan_command() {
  parse_scan_options "$@"
  if [[ -n "$SCAN_LIST" ]]; then
    [[ -f "$SCAN_LIST" ]] || { err "Domain list not found: $SCAN_LIST"; exit 1; }
    local d
    while IFS= read -r d || [[ -n "$d" ]]; do
      d="$(printf '%s' "$d" | sed 's/#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$d" ]] && continue
      scan_one "$d" || warn "Scan failed for $d; continuing."
    done <"$SCAN_LIST"
  elif [[ -n "$SCAN_DOMAIN" ]]; then
    scan_one "$SCAN_DOMAIN"
  else
    err "Missing domain. Example: thor scan example.com"
    exit 2
  fi
}

resume_command() {
  local dir="${1:-}"
  [[ -n "$dir" ]] || dir="$(latest_scan_dir || true)"
  [[ -n "$dir" ]] || { err "No previous scan found."; exit 1; }
  load_scan_state "$dir"
  validate_target_domain "$DOMAIN"
  run_pipeline
  generate_reports
  printf '\nResume complete. Reports are in: %s\n' "$SCAN_DIR"
}

report_command() {
  local dir="${1:-}"
  [[ -n "$dir" ]] || dir="$(latest_scan_dir || true)"
  [[ -n "$dir" ]] || { err "No scan directory found."; exit 1; }
  load_scan_state "$dir"
  generate_reports
}

clean_command() {
  local mode="${1:-}"
  if [[ "$mode" == "--all" ]]; then
    read -r -p "Delete all Thor results under $THOR_ROOT/$OUTPUT_DIR? Type DELETE: " ans
    if [[ "$ans" == "DELETE" ]]; then
      rm -rf "$THOR_ROOT/$OUTPUT_DIR"
      mkdir -p "$THOR_ROOT/$OUTPUT_DIR"
      info "All results removed."
    else
      warn "Clean cancelled."
    fi
  else
    find "$THOR_ROOT/$OUTPUT_DIR" -type d -name tmp -prune -exec rm -rf {} + 2>/dev/null || true
    info "Temporary files cleaned."
  fi
}

update_thor() {
  if [[ -d "$THOR_ROOT/.git" ]]; then
    git -C "$THOR_ROOT" pull --ff-only
  else
    warn "This Thor directory is not a git checkout. Download a new release or run update.sh from a git clone."
  fi
}

settings_menu() {
  local editor="${EDITOR:-nano}"
  "$editor" "$CONFIG_FILE"
}

view_reports_menu() {
  local latest
  latest="$(latest_scan_dir || true)"
  [[ -n "$latest" ]] || { warn "No reports found."; return 0; }
  printf 'Latest scan: %s\n' "$latest"
  ls -1 "$latest"/report.* 2>/dev/null || true
  if [[ -t 0 ]]; then
    read -r -p 'Open folder? [y/N] ' ans
    [[ "$(lower "$ans")" == y ]] && open_path "$latest"
  fi
}

interactive_menu() {
  while true; do
    banner
    cat <<'EOF'
1 Scan Domain
2 Scan Multiple Domains
3 View Reports
4 Resume Scan
5 Update Thor
6 Update Tools
7 Settings
8 Dependency Check
9 Help
0 Exit
EOF
    read -r -p 'Select: ' choice
    case "$choice" in
      1) read -r -p 'Domain: ' d; scan_command "$d" ;;
      2) read -r -p 'Domain list file: ' f; scan_command -l "$f" ;;
      3) view_reports_menu ;;
      4) resume_command ;;
      5) update_thor ;;
      6) update_tools ;;
      7) settings_menu ;;
      8) check_dependencies || true ;;
      9) usage ;;
      0) exit 0 ;;
      *) warn "Invalid choice." ;;
    esac
    read -r -p 'Press Enter to continue...' _
    clear || true
  done
}

main() {
  mkdir -p "$THOR_ROOT/$OUTPUT_DIR" "$THOR_ROOT/$LOG_DIR"
  case "${1:-}" in
    scan) shift; scan_command "$@" ;;
    resume) shift; resume_command "${1:-}" ;;
    update) update_thor ;;
    doctor) shift; if [[ "${1:-}" == "--install" ]]; then install_missing_dependencies; else check_dependencies || true; fi ;;
    report) shift; report_command "${1:-}" ;;
    history) print_history ;;
    clean) shift; clean_command "${1:-}" ;;
    gui) exec "$THOR_ROOT/gui/thor-gui.sh" ;;
    --help|-h|help) usage ;;
    --version|-v|version) printf 'Thor %s\n' "$THOR_VERSION" ;;
    "") interactive_menu ;;
    *) err "Unknown command: $1"; usage; exit 2 ;;
  esac
}

main "$@"
