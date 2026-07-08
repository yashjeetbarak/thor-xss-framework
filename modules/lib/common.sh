#!/usr/bin/env bash
# Common library for Thor. Sourced by thor.sh and all modules.
# shellcheck shell=bash

set -Eeuo pipefail
IFS=$'\n\t'

THOR_VERSION="1.0.0"
THOR_NAME="Thor"
THOR_TAGLINE="The Automated Recon & XSS Hunting Framework"

: "${THOR_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIG_FILE="${CONFIG_FILE:-$THOR_ROOT/config.conf}"
LOG_FILE=""
SCAN_DIR=""
TMP_DIR=""
STATE_FILE=""
DOMAIN=""
START_EPOCH="$(date +%s)"
CURRENT_STEP="idle"
TOTAL_STEPS="9"
COMPLETED_STEPS="0"

# Built-in defaults, overridden by config/env/CLI.
OUTPUT_DIR="results"
LOG_DIR="logs"
THREADS="50"
HTTPX_THREADS="100"
PARAMSPIDER_THREADS="20"
DALFOX_WORKERS="25"
DALFOX_TIMEOUT="10"
DALFOX_DELAY="0"
DALFOX_OUTPUT_FORMAT="plain"
DALFOX_FOLLOW_REDIRECTS="true"
DALFOX_REQUEST_METHOD="GET"
DALFOX_CUSTOM_PAYLOAD_FILE=""
DALFOX_SAVE_RAW_JSON="false"
DALFOX_RETRIES="1"
DALFOX_BATCH_SIZE="250"
DALFOX_PRECHECK_LIVE="true"
DALFOX_REQUIRE_LIVE_HOSTS="true"
DALFOX_SCOPE_ONLY="true"
DALFOX_MAX_TARGETS_PER_HOST="0"
DALFOX_ULIMIT="8192"
DALFOX_USE_OUTPUT_FLAG="false"
KATANA_DEPTH="2"
KATANA_CONCURRENCY="20"
MAX_URLCOLLECT_HOSTS="250"
ENABLE_HTTPX="true"
ENABLE_PARAMSPIDER="true"
ENABLE_GAU="true"
ENABLE_WAYMORE="true"
ENABLE_KATANA="true"
SAVE_JSON="true"
SAVE_HTML="true"
VERBOSE="false"
DEBUG="false"
SILENT="false"
RETRY="3"
PROXY=""
COOKIES=""
HEADERS=""
USER_AGENT="Thor/1.0.0"
ALLOW_PRIVATE_TARGETS="false"
CLEAN_TEMP="true"

usage() {
  cat <<'EOF'
Thor - The Automated Recon & XSS Hunting Framework

Usage:
  thor                         Interactive menu
  thor scan example.com        Scan a single authorized domain
  thor scan -l domains.txt     Scan authorized domains from a file
  thor resume                  Resume the latest incomplete scan
  thor resume /path/to/scan    Resume a specific scan directory
  thor doctor [--install]      Check dependencies, optionally install missing tools
  thor report [scan_dir]       Regenerate reports for a scan
  thor history                 Show scan history
  thor clean [--all]           Clean temporary files; --all also removes scan results after confirmation
  thor update                  Update Thor repository
  thor gui                     Launch Zenity/YAD GUI
  thor --version               Show version
  thor --help                  Show help

Useful Dalfox scan options:
  --dalfox-workers N           Worker count. Default is conservative to avoid open-file errors.
  --dalfox-batch-size N        Split Dalfox input into safe batches. 0 disables batching.
  --dalfox-retries N           Retry failed Dalfox batches.
  --no-dalfox-precheck-live    Skip URL-level httpx precheck before Dalfox.

Safety:
  Use Thor only on systems you own or are explicitly authorized to test.
EOF
}

banner() {
  cat <<'EOF'
 _______ _                 
|__   __| |                
   | |  | |__   ___  _ __  
   | |  | '_ \ / _ \| '__| 
   | |  | | | | (_) | |    
   |_|  |_| |_|\___/|_|    
The Automated Recon & XSS Hunting Framework
EOF
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_true() {
  case "$(lower "${1:-false}")" in
    1|true|yes|y|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

now_iso() { date '+%Y-%m-%dT%H:%M:%S%z'; }

log_init() {
  local log_dir="${THOR_ROOT}/${LOG_DIR}"
  if [[ -n "${SCAN_DIR:-}" && -d "${SCAN_DIR:-}" ]]; then
    LOG_FILE="${LOG_FILE:-$SCAN_DIR/logs.txt}"
  else
    mkdir -p "$log_dir"
    LOG_FILE="${LOG_FILE:-$log_dir/thor.log}"
  fi
  touch "$LOG_FILE"
}

log_msg() {
  local level="$1"
  shift
  local msg="$*"
  log_init
  printf '[%s] [%s] %s\n' "$(now_iso)" "$level" "$msg" >>"$LOG_FILE"
  if [[ "$level" == "ERROR" || "$level" == "WARNING" || "${VERBOSE}" == "true" || "${DEBUG}" == "true" ]]; then
    printf '[%s] %s\n' "$level" "$msg" >&2
  fi
}

info() { log_msg INFO "$*"; is_true "$SILENT" || printf '[*] %s\n' "$*"; }
warn() { log_msg WARNING "$*"; printf '[!] %s\n' "$*" >&2; }
err() { log_msg ERROR "$*"; printf '[x] %s\n' "$*" >&2; }
debug() { is_true "$DEBUG" && log_msg DEBUG "$*" || true; }

validate_positive_int() {
  local name="$1" val
  val="${!name}"
  if ! [[ "$val" =~ ^[1-9][0-9]*$ ]]; then
    err "$name must be a positive integer; got '$val'"
    exit 2
  fi
}

validate_nonnegative_int() {
  local name="$1" val
  val="${!name}"
  if ! [[ "$val" =~ ^[0-9]+$ ]]; then
    err "$name must be a non-negative integer; got '$val'"
    exit 2
  fi
}

load_config() {
  local cfg="${1:-$CONFIG_FILE}"
  if [[ -f "$cfg" ]]; then
    # shellcheck disable=SC1090
    source "$cfg"
  fi

  OUTPUT_DIR="${THOR_OUTPUT_DIR:-${OUTPUT_DIR}}"
  LOG_DIR="${THOR_LOG_DIR:-${LOG_DIR}}"
  THREADS="${THOR_THREADS:-${THREADS}}"
  HTTPX_THREADS="${THOR_HTTPX_THREADS:-${HTTPX_THREADS}}"
  PARAMSPIDER_THREADS="${THOR_PARAMSPIDER_THREADS:-${PARAMSPIDER_THREADS}}"
  DALFOX_WORKERS="${THOR_DALFOX_WORKERS:-${DALFOX_WORKERS}}"
  DALFOX_TIMEOUT="${THOR_DALFOX_TIMEOUT:-${DALFOX_TIMEOUT}}"
  DALFOX_DELAY="${THOR_DALFOX_DELAY:-${DALFOX_DELAY}}"
  DALFOX_OUTPUT_FORMAT="${THOR_DALFOX_OUTPUT_FORMAT:-${DALFOX_OUTPUT_FORMAT}}"
  DALFOX_FOLLOW_REDIRECTS="${THOR_DALFOX_FOLLOW_REDIRECTS:-${DALFOX_FOLLOW_REDIRECTS}}"
  DALFOX_REQUEST_METHOD="${THOR_DALFOX_REQUEST_METHOD:-${DALFOX_REQUEST_METHOD}}"
  DALFOX_CUSTOM_PAYLOAD_FILE="${THOR_DALFOX_CUSTOM_PAYLOAD_FILE:-${DALFOX_CUSTOM_PAYLOAD_FILE}}"
  DALFOX_SAVE_RAW_JSON="${THOR_DALFOX_SAVE_RAW_JSON:-${DALFOX_SAVE_RAW_JSON}}"
  DALFOX_RETRIES="${THOR_DALFOX_RETRIES:-${DALFOX_RETRIES}}"
  DALFOX_BATCH_SIZE="${THOR_DALFOX_BATCH_SIZE:-${DALFOX_BATCH_SIZE}}"
  DALFOX_PRECHECK_LIVE="${THOR_DALFOX_PRECHECK_LIVE:-${DALFOX_PRECHECK_LIVE}}"
  DALFOX_REQUIRE_LIVE_HOSTS="${THOR_DALFOX_REQUIRE_LIVE_HOSTS:-${DALFOX_REQUIRE_LIVE_HOSTS}}"
  DALFOX_SCOPE_ONLY="${THOR_DALFOX_SCOPE_ONLY:-${DALFOX_SCOPE_ONLY}}"
  DALFOX_MAX_TARGETS_PER_HOST="${THOR_DALFOX_MAX_TARGETS_PER_HOST:-${DALFOX_MAX_TARGETS_PER_HOST}}"
  DALFOX_ULIMIT="${THOR_DALFOX_ULIMIT:-${DALFOX_ULIMIT}}"
  DALFOX_USE_OUTPUT_FLAG="${THOR_DALFOX_USE_OUTPUT_FLAG:-${DALFOX_USE_OUTPUT_FLAG}}"
  KATANA_DEPTH="${THOR_KATANA_DEPTH:-${KATANA_DEPTH}}"
  KATANA_CONCURRENCY="${THOR_KATANA_CONCURRENCY:-${KATANA_CONCURRENCY}}"
  MAX_URLCOLLECT_HOSTS="${THOR_MAX_URLCOLLECT_HOSTS:-${MAX_URLCOLLECT_HOSTS}}"
  ENABLE_HTTPX="${THOR_ENABLE_HTTPX:-${ENABLE_HTTPX}}"
  ENABLE_PARAMSPIDER="${THOR_ENABLE_PARAMSPIDER:-${ENABLE_PARAMSPIDER}}"
  ENABLE_GAU="${THOR_ENABLE_GAU:-${ENABLE_GAU}}"
  ENABLE_WAYMORE="${THOR_ENABLE_WAYMORE:-${ENABLE_WAYMORE}}"
  ENABLE_KATANA="${THOR_ENABLE_KATANA:-${ENABLE_KATANA}}"
  SAVE_JSON="${THOR_SAVE_JSON:-${SAVE_JSON}}"
  SAVE_HTML="${THOR_SAVE_HTML:-${SAVE_HTML}}"
  VERBOSE="${THOR_VERBOSE:-${VERBOSE}}"
  DEBUG="${THOR_DEBUG:-${DEBUG}}"
  SILENT="${THOR_SILENT:-${SILENT}}"
  RETRY="${THOR_RETRY:-${RETRY}}"
  PROXY="${THOR_PROXY:-${PROXY}}"
  COOKIES="${THOR_COOKIES:-${COOKIES}}"
  HEADERS="${THOR_HEADERS:-${HEADERS}}"
  USER_AGENT="${THOR_USER_AGENT:-${USER_AGENT}}"
  ALLOW_PRIVATE_TARGETS="${THOR_ALLOW_PRIVATE_TARGETS:-${ALLOW_PRIVATE_TARGETS}}"
  CLEAN_TEMP="${THOR_CLEAN_TEMP:-${CLEAN_TEMP}}"

  validate_positive_int THREADS
  validate_positive_int HTTPX_THREADS
  validate_positive_int PARAMSPIDER_THREADS
  validate_positive_int DALFOX_WORKERS
  validate_positive_int DALFOX_TIMEOUT
  validate_nonnegative_int DALFOX_DELAY
  validate_positive_int DALFOX_RETRIES
  validate_nonnegative_int DALFOX_BATCH_SIZE
  validate_nonnegative_int DALFOX_MAX_TARGETS_PER_HOST
  validate_nonnegative_int DALFOX_ULIMIT
  validate_positive_int RETRY
}

normalize_domain() {
  local raw="$1"
  raw="${raw#http://}"
  raw="${raw#https://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  raw="${raw%.}"
  lower "$raw"
}

is_valid_domain() {
  local d="$1"
  [[ ${#d} -le 253 ]] || return 1
  [[ "$d" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

is_private_or_local_target() {
  local d="$1"
  [[ "$d" == localhost || "$d" == *.local || "$d" == *.internal || "$d" == *.lan || "$d" == *.home ]] && return 0
  [[ "$d" =~ ^(10|127)\. ]] && return 0
  [[ "$d" =~ ^192\.168\. ]] && return 0
  [[ "$d" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && return 0
  return 1
}

validate_target_domain() {
  local d="$1"
  if ! is_valid_domain "$d"; then
    err "Invalid domain: $d"
    return 1
  fi
  if ! is_true "$ALLOW_PRIVATE_TARGETS" && is_private_or_local_target "$d"; then
    err "Refusing private/internal target '$d'. Set ALLOW_PRIVATE_TARGETS=true only for authorized lab scopes."
    return 1
  fi
}

safe_name() { printf '%s' "$1" | sed -E 's#[^A-Za-z0-9._-]+#_#g; s#^_+##; s#_+$##'; }

init_scan_dir() {
  DOMAIN="$1"
  local ts
  ts="$(date '+%Y-%m-%d_%H-%M-%S')"
  SCAN_DIR="${THOR_ROOT}/${OUTPUT_DIR}/${DOMAIN}/${ts}"
  mkdir -p "$SCAN_DIR" "$SCAN_DIR/paramspider" "$SCAN_DIR/tmp"
  TMP_DIR="$SCAN_DIR/tmp"
  STATE_FILE="$SCAN_DIR/state.env"
  LOG_FILE="$SCAN_DIR/logs.txt"
  touch "$LOG_FILE"
  {
    printf 'DOMAIN=%q\n' "$DOMAIN"
    printf 'SCAN_DIR=%q\n' "$SCAN_DIR"
    printf 'CREATED_AT=%q\n' "$(now_iso)"
  } >"$STATE_FILE"
  info "Scan directory: $SCAN_DIR"
}

load_scan_state() {
  local dir="$1"
  if [[ ! -d "$dir" || ! -f "$dir/state.env" ]]; then
    err "No resumable scan state found at: $dir"
    return 1
  fi
  SCAN_DIR="$(cd "$dir" && pwd)"
  STATE_FILE="$SCAN_DIR/state.env"
  LOG_FILE="$SCAN_DIR/logs.txt"
  TMP_DIR="$SCAN_DIR/tmp"
  mkdir -p "$TMP_DIR"
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  DOMAIN="${DOMAIN:-$(basename "$(dirname "$SCAN_DIR")")}"
  info "Resuming scan: $SCAN_DIR"
}

state_get() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 1
  grep -E "^${key}=" "$STATE_FILE" | tail -n 1 | cut -d= -f2- | sed "s/^'//; s/'$//" || true
}

mark_step_done() {
  local step="$1" duration="${2:-0}" key
  key="$(safe_name "$step" | tr '[:lower:]' '[:upper:]')"
  {
    printf 'STEP_%s_DONE=%q\n' "$key" "true"
    printf 'STEP_%s_DURATION=%q\n' "$key" "$duration"
    printf 'LAST_COMPLETED_STEP=%q\n' "$step"
    printf 'UPDATED_AT=%q\n' "$(now_iso)"
  } >>"$STATE_FILE"
}

step_done() {
  local step="$1" key
  key="STEP_$(safe_name "$step" | tr '[:lower:]' '[:upper:]')_DONE"
  [[ "$(state_get "$key")" == "true" ]]
}

record_metric() {
  local key="$1" val="$2"
  printf 'METRIC_%s=%q\n' "$(safe_name "$key" | tr '[:lower:]' '[:upper:]')" "$val" >>"$STATE_FILE"
}

count_lines() {
  local file="$1"
  [[ -f "$file" ]] || { printf '0'; return; }
  awk 'NF {count++} END {print count + 0}' "$file" 2>/dev/null || printf '0'
}

dedup_file() {
  local file="$1" tmpbase tmp
  [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && tmpbase="$TMP_DIR" || tmpbase="/tmp"
  [[ -f "$file" ]] || { : >"$file"; return 0; }
  tmp="$(mktemp "$tmpbase/thor-dedup.XXXXXX")"
  awk 'NF {gsub(/\r/, ""); print}' "$file" | sort -u >"$tmp"
  mv "$tmp" "$file"
}

normalize_domain_file() {
  local in="$1" out="$2"
  : >"$out"
  [[ -f "$in" ]] || return 0
  awk '{print $0}' "$in" \
    | sed -E 's#https?://##; s#/.*$##; s#:.*$##; s#\.$##' \
    | tr '[:upper:]' '[:lower:]' \
    | grep -E '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' \
    | sort -u >"$out" || true
}

extract_urls() { grep -Eo "https?://[^[:space:]\"'<>)]*" | sed -E 's/[),.;]+$//'; }
filter_static_resources() { grep -Eiv '\.(jpg|jpeg|png|gif|ico|css|js|svg|webp|mp4|m4v|mov|zip|rar|7z|tar|gz|pdf|woff|woff2|ttf|eot|otf|map|xml|txt|csv|doc|docx|xls|xlsx|ppt|pptx)(\?|#|$)'; }

trim_line() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

quote_cmd() {
  local out="" arg
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    out+="$arg "
  done
  printf '%s' "${out% }"
}

log_command_result() {
  local label="$1" status="$2" duration="$3" stdout_file="$4" stderr_file="$5"
  shift 5
  {
    printf '[%s] [COMMAND] label=%s\n' "$(now_iso)" "$label"
    printf '[%s] [COMMAND] cmd=%s\n' "$(now_iso)" "$(quote_cmd "$@")"
    printf '[%s] [COMMAND] exit_code=%s elapsed_seconds=%s\n' "$(now_iso)" "$status" "$duration"
    printf '[%s] [STDOUT] label=%s begin\n' "$(now_iso)" "$label"
    [[ -s "$stdout_file" ]] && cat "$stdout_file"
    printf '[%s] [STDOUT] label=%s end\n' "$(now_iso)" "$label"
    printf '[%s] [STDERR] label=%s begin\n' "$(now_iso)" "$label"
    [[ -s "$stderr_file" ]] && cat "$stderr_file"
    printf '[%s] [STDERR] label=%s end\n' "$(now_iso)" "$label"
  } >>"$LOG_FILE"
}

run_command_capture() {
  local label="$1" stdout_file="$2" stderr_file="$3"
  shift 3
  local start status duration tmpbase
  [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && tmpbase="$TMP_DIR" || tmpbase="/tmp"
  : >"$stdout_file"
  : >"$stderr_file"
  start="$(date +%s)"
  log_msg INFO "Command start: $label :: $(quote_cmd "$@")"
  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  duration=$(( $(date +%s) - start ))
  log_command_result "$label" "$status" "$duration" "$stdout_file" "$stderr_file" "$@"
  return "$status"
}

retry_command() {
  local label="$1"
  shift
  local attempt=1 max="${RETRY:-3}" start status duration stdout_file stderr_file tmpbase
  [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && tmpbase="$TMP_DIR" || tmpbase="/tmp"
  while (( attempt <= max )); do
    stdout_file="$(mktemp "$tmpbase/thor-cmd-stdout.XXXXXX")"
    stderr_file="$(mktemp "$tmpbase/thor-cmd-stderr.XXXXXX")"
    start="$(date +%s)"
    log_msg INFO "Attempt $attempt/$max: $label :: $(quote_cmd "$@")"
    set +e
    "$@" >"$stdout_file" 2>"$stderr_file"
    status=$?
    set -e
    duration=$(( $(date +%s) - start ))
    log_command_result "$label attempt $attempt/$max" "$status" "$duration" "$stdout_file" "$stderr_file" "$@"
    if (( status == 0 )); then
      cat "$stdout_file" >>"$LOG_FILE"
      rm -f "$stdout_file" "$stderr_file"
      log_msg INFO "Success: $label (${duration}s)"
      return 0
    fi
    warn "Failed attempt $attempt/$max for $label with status $status after ${duration}s"
    rm -f "$stdout_file" "$stderr_file"
    attempt=$(( attempt + 1 ))
    sleep $(( attempt < 6 ? attempt : 5 ))
  done
  log_msg ERROR "Giving up after $max attempts: $label"
  return 1
}

retry_command_output() {
  local label="$1" outfile="$2" mode="$3"
  shift 3
  local attempt=1 max="${RETRY:-3}" start status duration stdout_file stderr_file tmpbase
  [[ "$mode" == "append" || "$mode" == "truncate" ]] || { err "retry_command_output mode must be append or truncate"; return 2; }
  [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && tmpbase="$TMP_DIR" || tmpbase="/tmp"
  [[ "$mode" == "truncate" ]] && : >"$outfile"
  while (( attempt <= max )); do
    stdout_file="$(mktemp "$tmpbase/thor-cmd-stdout.XXXXXX")"
    stderr_file="$(mktemp "$tmpbase/thor-cmd-stderr.XXXXXX")"
    start="$(date +%s)"
    log_msg INFO "Attempt $attempt/$max: $label :: $(quote_cmd "$@")"
    set +e
    "$@" >"$stdout_file" 2>"$stderr_file"
    status=$?
    set -e
    duration=$(( $(date +%s) - start ))
    log_command_result "$label attempt $attempt/$max" "$status" "$duration" "$stdout_file" "$stderr_file" "$@"
    if (( status == 0 )); then
      if [[ "$mode" == "append" ]]; then cat "$stdout_file" >>"$outfile"; else cat "$stdout_file" >"$outfile"; fi
      rm -f "$stdout_file" "$stderr_file"
      log_msg INFO "Success: $label (${duration}s)"
      return 0
    fi
    warn "Failed attempt $attempt/$max for $label with status $status after ${duration}s"
    rm -f "$stdout_file" "$stderr_file"
    attempt=$(( attempt + 1 ))
    sleep $(( attempt < 6 ? attempt : 5 ))
  done
  log_msg ERROR "Giving up after $max attempts: $label"
  return 1
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

resolve_httpx() {
  if command_exists httpx; then printf 'httpx'; elif command_exists httpx-toolkit; then printf 'httpx-toolkit'; else return 1; fi
}

elapsed_seconds() { printf '%s' "$(( $(date +%s) - START_EPOCH ))"; }

human_time() {
  local s="${1:-0}"
  printf '%02d:%02d:%02d' "$((s/3600))" "$(((s%3600)/60))" "$((s%60))"
}

progress_line() {
  local tool="$1" target="$2" completed="$3" total="$4" urls="$5" subs="$6"
  local pct=0 eta='--:--:--' elapsed
  elapsed="$(elapsed_seconds)"
  if (( total > 0 )); then
    pct=$(( completed * 100 / total ))
    if (( completed > 0 )); then eta="$(human_time $(( elapsed * (total - completed) / completed )))"; fi
  fi
  is_true "$SILENT" || printf '\r[%3d%%] Tool=%s Target=%s Elapsed=%s ETA=%s URLs=%s Subdomains=%s    ' \
    "$pct" "$tool" "$target" "$(human_time "$elapsed")" "$eta" "$urls" "$subs"
}

progress_done() { is_true "$SILENT" || printf '\n'; }

cleanup() {
  local status=$?
  if [[ -n "${SCAN_DIR:-}" && -d "${SCAN_DIR:-}" ]]; then
    if is_true "$CLEAN_TEMP" && [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]]; then rm -rf "$TMP_DIR" || true; fi
    log_msg INFO "Cleanup completed with exit status $status"
  fi
  return "$status"
}

ctrl_c() {
  warn "Cancellation requested. Saving partial results and state for resume."
  if [[ -n "${STATE_FILE:-}" && -f "${STATE_FILE:-}" ]]; then
    printf 'INTERRUPTED_AT=%q\n' "$(now_iso)" >>"$STATE_FILE"
    printf 'CURRENT_STEP=%q\n' "${CURRENT_STEP:-unknown}" >>"$STATE_FILE"
  fi
  cleanup || true
  exit 130
}

trap cleanup EXIT
trap ctrl_c INT TERM

latest_scan_dir() {
  local base="${THOR_ROOT}/${OUTPUT_DIR}"
  [[ -d "$base" ]] || return 1
  find "$base" -mindepth 2 -maxdepth 2 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {sub(/^[^ ]+ /, ""); print}'
}

print_history() {
  local base="${THOR_ROOT}/${OUTPUT_DIR}"
  [[ -d "$base" ]] || { info "No scans yet."; return 0; }
  find "$base" -mindepth 2 -maxdepth 2 -type d -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort -r | head -n 50
}

open_path() {
  local path="$1"
  if command_exists xdg-open; then xdg-open "$path" >/dev/null 2>&1 || true; else printf '%s\n' "$path"; fi
}


# Extract a lowercase hostname from a URL. Prints empty string on malformed input.
url_host() {
  local url="$1" host
  host="${url#http://}"
  host="${host#https://}"
  host="${host%%/*}"
  host="${host%%\?*}"
  host="${host%%:*}"
  lower "$host"
}

# Returns success if host is the current authorized domain or one of its subdomains.
host_in_scope() {
  local host="$1" domain="${2:-$DOMAIN}" suffix
  host="$(lower "$host")"
  domain="$(lower "$domain")"
  suffix=".${domain}"
  [[ "$host" == "$domain" || "$host" == *"$suffix" ]]
}

# Build the host allow-list used before Dalfox. Prefer live_hosts.txt when available.
build_dalfox_allowed_hosts() {
  local out="$1"
  : >"$out"
  if is_true "$DALFOX_REQUIRE_LIVE_HOSTS" && [[ -s "${SCAN_DIR:-}/live_hosts.txt" ]]; then
    normalize_domain_file "$SCAN_DIR/live_hosts.txt" "$out"
  elif [[ -s "${SCAN_DIR:-}/subdomains.txt" ]]; then
    normalize_domain_file "$SCAN_DIR/subdomains.txt" "$out"
  fi
  if [[ -n "${DOMAIN:-}" ]]; then printf '%s\n' "$DOMAIN" >>"$out"; fi
  dedup_file "$out"
}

# Strict URL validation for Dalfox. This is intentionally scope-aware and rejects
# third-party URLs from archives/crawlers, malformed values, multi-parameter URLs,
# static assets, and non-live hosts when live host data exists.
validate_url_file_for_dalfox() {
  local input="$1" valid_out="$2" skipped_out="$3"
  local tmpbase tmp_valid tmp_skip allowed_hosts
  [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && tmpbase="$TMP_DIR" || tmpbase="/tmp"
  tmp_valid="$(mktemp "$tmpbase/thor-valid-urls.XXXXXX")"
  tmp_skip="$(mktemp "$tmpbase/thor-skipped-urls.XXXXXX")"
  allowed_hosts="$(mktemp "$tmpbase/thor-allowed-hosts.XXXXXX")"
  : >"$tmp_valid"
  : >"$tmp_skip"
  build_dalfox_allowed_hosts "$allowed_hosts"

  if [[ ! -e "$input" ]]; then
    printf 'missing_input_file\t%s\n' "$input" >"$tmp_skip"
  elif [[ ! -r "$input" ]]; then
    printf 'unreadable_input_file\t%s\n' "$input" >"$tmp_skip"
  else
    awk -v domain="${DOMAIN:-}" \
        -v scope_only="$(is_true "$DALFOX_SCOPE_ONLY" && printf true || printf false)" \
        -v require_live="$(is_true "$DALFOX_REQUIRE_LIVE_HOSTS" && printf true || printf false)" \
        -v allowed_file="$allowed_hosts" \
        -v valid="$tmp_valid" \
        -v skipped="$tmp_skip" '
      BEGIN {
        IGNORECASE=1
        while ((getline h < allowed_file) > 0) { if (h != "") { allowed[tolower(h)] = 1; allowed_count++ } }
      }
      function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
      function lower_s(s) { return tolower(s) }
      function host_from_url(u, h) {
        h=u
        sub(/^https?:\/\//, "", h)
        sub(/[\/?#:].*$/, "", h)
        return tolower(h)
      }
      function path_from_url(u, p) {
        p=u
        sub(/^https?:\/\/[^\/]+/, "", p)
        sub(/[?#].*$/, "", p)
        return p
      }
      function in_scope(h, suffix) {
        h=tolower(h); suffix="." tolower(domain)
        return (domain == "" || h == tolower(domain) || substr(h, length(h)-length(suffix)+1) == suffix)
      }
      function reject(reason, u) { print reason "\t" u >> skipped }
      {
        raw=$0
        gsub(/\r/, "", raw)
        url=trim(raw)
        gsub(/FUZZ/, "123", url)
        reason=""
        host=host_from_url(url)
        path=path_from_url(url)
        query=url
        sub(/^.*\?/, "", query)
        sub(/#.*/, "", query)

        if (url == "") reason="empty_line"
        else if (url !~ /^https?:\/\//) reason="unsupported_protocol"
        else if (url ~ /[[:space:]]/) reason="contains_whitespace"
        else if (host == "" || host !~ /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/) reason="invalid_host"
        else if (scope_only == "true" && !in_scope(host)) reason="out_of_scope_host"
        else if (require_live == "true" && allowed_count > 0 && !(host in allowed)) reason="host_not_live"
        else if (url !~ /\?/) reason="missing_query"
        else if (url ~ /&/) reason="multi_parameter_url"
        else if (query !~ /^[A-Za-z0-9._~%+-]+=[^&#[:space:]]*$/) reason="invalid_or_unsupported_parameter"
        else if (path ~ /\.(jpg|jpeg|png|gif|ico|css|js|svg|webp|mp4|m4v|mov|zip|rar|7z|tar|gz|pdf|woff|woff2|ttf|eot|otf|map|xml|txt|csv|doc|docx|xls|xlsx|ppt|pptx)$/) reason="static_resource"

        if (reason != "") reject(reason, url)
        else print url >> valid
      }
    ' "$input"
  fi

  sort -u "$tmp_valid" >"$valid_out"
  sort -u "$tmp_skip" >"$skipped_out"
  rm -f "$tmp_valid" "$tmp_skip" "$allowed_hosts"
}
