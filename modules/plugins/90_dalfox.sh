#!/usr/bin/env bash
# XSS testing with Dalfox. This module only orchestrates Dalfox against authorized inputs.
# shellcheck shell=bash

DALFOX_LAST_CMD=""
DALFOX_LAST_EXIT="0"
DALFOX_LAST_STDERR=""
DALFOX_ERROR_REASON=""
DALFOX_CMD=()
DALFOX_SCOPED_HELP=""
DALFOX_BASE_MODE=""
DALFOX_EFFECTIVE_WORKERS=""

dalfox_help_file() { dalfox file --help 2>&1 | tr -d '\r' || true; }
dalfox_help_scan() { dalfox scan --help 2>&1 | tr -d '\r' || true; }
dalfox_help_global() { dalfox --help 2>&1 | tr -d '\r' || true; }

dalfox_supports() {
  local help="$1" pattern="$2"
  grep -Eiq -- "$pattern" <<<"$help"
}

dalfox_raise_ulimit() {
  local desired="${DALFOX_ULIMIT:-0}" current
  [[ "$desired" =~ ^[0-9]+$ ]] || return 0
  ((desired > 0)) || return 0
  current="$(ulimit -n 2>/dev/null || printf '0')"
  if [[ "$current" =~ ^[0-9]+$ ]] && ((current < desired)); then
    ulimit -n "$desired" 2>/dev/null || warn "Could not raise open-file limit to $desired; current limit is $current."
  fi
}

# Build the base command and return help scoped to that exact subcommand.
# Do not combine global/file/scan help: Dalfox v3 may expose different flags
# per subcommand. Mixing help caused invalid --worker/--workers choices.
dalfox_build_base_cmd() {
  local input="$1" mode_help
  DALFOX_CMD=()
  DALFOX_BASE_MODE=""

  mode_help="$(dalfox_help_file)"
  if grep -Eiq 'Usage:.*dalfox[[:space:]]+file|dalfox file|FILE|--workers|--worker' <<<"$mode_help"; then
    DALFOX_CMD=(dalfox file "$input")
    DALFOX_BASE_MODE="file"
    DALFOX_SCOPED_HELP="$mode_help"
    return 0
  fi

  mode_help="$(dalfox_help_scan)"
  if grep -Eiq 'Usage:.*dalfox[[:space:]]+scan|dalfox scan|--file|-F|URL' <<<"$mode_help"; then
    if dalfox_supports "$mode_help" '(^|[[:space:]])-F([,[:space:]]|$)|(^|[[:space:]])--file([,[:space:]]|$)'; then
      DALFOX_CMD=(dalfox scan -F "$input")
    else
      DALFOX_CMD=(dalfox scan "$input")
    fi
    DALFOX_BASE_MODE="scan"
    DALFOX_SCOPED_HELP="$mode_help"
    return 0
  fi

  # Last-resort fallback for older installations with sparse help output.
  DALFOX_CMD=(dalfox file "$input")
  DALFOX_BASE_MODE="file"
  DALFOX_SCOPED_HELP="$(dalfox_help_global)"
}

dalfox_add_common_flags() {
  local help="$1" mode="$2" line_count="$3" header_line max_targets

  # v3 file mode uses --workers. Older builds may use --worker or -w.
  # Prefer the exact flag exposed by the selected subcommand help.
  if dalfox_supports "$help" '(^|[[:space:]])--workers([,[:space:]]|$|[[:space:]]+<)'; then
    DALFOX_CMD+=(--workers "$DALFOX_EFFECTIVE_WORKERS")
  elif dalfox_supports "$help" '(^|[[:space:]])--worker([,[:space:]]|$|[[:space:]]+<)'; then
    DALFOX_CMD+=(--worker "$DALFOX_EFFECTIVE_WORKERS")
  elif dalfox_supports "$help" '(^|[[:space:]])-w([,[:space:]]|$)'; then
    DALFOX_CMD+=(-w "$DALFOX_EFFECTIVE_WORKERS")
  fi

  if dalfox_supports "$help" '(^|[[:space:]])--timeout([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--timeout "$DALFOX_TIMEOUT"); fi
  if [[ "$DALFOX_DELAY" != "0" ]] && dalfox_supports "$help" '(^|[[:space:]])--delay([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--delay "$DALFOX_DELAY"); fi
  if [[ -n "$PROXY" ]] && dalfox_supports "$help" '(^|[[:space:]])--proxy([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--proxy "$PROXY"); fi
  if [[ -n "$COOKIES" ]] && dalfox_supports "$help" '(^|[[:space:]])(--cookie|-C)([,[:space:]]|$|[[:space:]]+<)'; then
    if dalfox_supports "$help" '(^|[[:space:]])--cookie([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--cookie "$COOKIES"); else DALFOX_CMD+=(-C "$COOKIES"); fi
  fi
  if [[ -n "$HEADERS" ]] && dalfox_supports "$help" '(^|[[:space:]])(--header|-H)([,[:space:]]|$|[[:space:]]+<)'; then
    while IFS= read -r header_line; do
      [[ -n "$header_line" ]] || continue
      if dalfox_supports "$help" '(^|[[:space:]])--header([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--header "$header_line"); else DALFOX_CMD+=(-H "$header_line"); fi
    done < <(printf '%b\n' "$HEADERS")
  fi
  if [[ -n "$USER_AGENT" ]] && dalfox_supports "$help" '(^|[[:space:]])(--user-agent|-A)([,[:space:]]|$|[[:space:]]+<)'; then
    if dalfox_supports "$help" '(^|[[:space:]])--user-agent([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--user-agent "$USER_AGENT"); else DALFOX_CMD+=(-A "$USER_AGENT"); fi
  fi
  if is_true "$DALFOX_FOLLOW_REDIRECTS" && dalfox_supports "$help" '(^|[[:space:]])--follow-redirects([,[:space:]]|$)'; then DALFOX_CMD+=(--follow-redirects); fi
  if [[ -n "$DALFOX_REQUEST_METHOD" && "$DALFOX_REQUEST_METHOD" != "GET" ]] && dalfox_supports "$help" '(^|[[:space:]])(--method|-X)([,[:space:]]|$|[[:space:]]+<)'; then
    if dalfox_supports "$help" '(^|[[:space:]])--method([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--method "$DALFOX_REQUEST_METHOD"); else DALFOX_CMD+=(-X "$DALFOX_REQUEST_METHOD"); fi
  fi
  if [[ -n "$DALFOX_CUSTOM_PAYLOAD_FILE" ]] && [[ -f "$DALFOX_CUSTOM_PAYLOAD_FILE" ]]; then
    if dalfox_supports "$help" '(^|[[:space:]])--custom-payload-file([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--custom-payload-file "$DALFOX_CUSTOM_PAYLOAD_FILE")
    elif dalfox_supports "$help" '(^|[[:space:]])--custom-payload([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--custom-payload "$DALFOX_CUSTOM_PAYLOAD_FILE")
    fi
  fi
  max_targets="${DALFOX_MAX_TARGETS_PER_HOST:-0}"
  if [[ ! "$max_targets" =~ ^[0-9]+$ ]]; then max_targets="0"; fi
  if (( max_targets == 0 )); then max_targets="$line_count"; fi
  if (( max_targets > 0 )) && dalfox_supports "$help" '(^|[[:space:]])--max-targets-per-host([,[:space:]]|$|[[:space:]]+<)'; then
    DALFOX_CMD+=(--max-targets-per-host "$max_targets")
  fi
  if is_true "$DEBUG" && dalfox_supports "$help" '(^|[[:space:]])--debug([,[:space:]]|$)'; then DALFOX_CMD+=(--debug); fi
  if is_true "$SILENT" && dalfox_supports "$help" '(^|[[:space:]])(--silence|--silent|-S)([,[:space:]]|$)'; then
    if dalfox_supports "$help" '(^|[[:space:]])--silence([,[:space:]]|$)'; then DALFOX_CMD+=(--silence); elif dalfox_supports "$help" '(^|[[:space:]])--silent([,[:space:]]|$)'; then DALFOX_CMD+=(--silent); else DALFOX_CMD+=(-S); fi
  fi

  if [[ "$mode" == "json" ]]; then
    if dalfox_supports "$help" '(^|[[:space:]])--format([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--format json)
    elif dalfox_supports "$help" '(^|[[:space:]])--output-format([,[:space:]]|$|[[:space:]]+<)'; then DALFOX_CMD+=(--output-format json)
    else return 2
    fi
  fi
}

dalfox_error_reason() {
  local file="$1" data
  data="$(cat "$file" 2>/dev/null || true)"
  if grep -Eiq 'too many open files|os error 24|EMFILE' <<<"$data"; then printf 'too_many_open_files'; return 0; fi
  if grep -Eiq 'unexpected argument|unknown option|invalid flag|Found argument' <<<"$data"; then printf 'invalid_flag'; return 0; fi
  if grep -Eiq 'permission denied|operation not permitted' <<<"$data"; then printf 'permission_denied'; return 0; fi
  if grep -Eiq 'no such file|cannot find|not found' <<<"$data"; then printf 'missing_file_or_binary'; return 0; fi
  if grep -Eiq 'timeout|deadline exceeded' <<<"$data"; then printf 'timeout_exceeded'; return 0; fi
  if grep -Eiq 'connection refused' <<<"$data"; then printf 'connection_refused'; return 0; fi
  if grep -Eiq 'error:|ERROR|panic|fatal' <<<"$data"; then printf 'dalfox_error'; return 0; fi
  printf 'warning_or_no_findings'
}

dalfox_is_hard_error() {
  case "$1" in
    too_many_open_files|invalid_flag|permission_denied|missing_file_or_binary|timeout_exceeded|dalfox_error) return 0 ;;
    *) return 1 ;;
  esac
}

dalfox_run_batch_once() {
  local batch_file="$1" stdout_file="$2" stderr_file="$3" line_count="$4"
  local help
  dalfox_build_base_cmd "$batch_file"
  help="$DALFOX_SCOPED_HELP"
  dalfox_add_common_flags "$help" "text" "$line_count"
  DALFOX_LAST_CMD="$(quote_cmd "${DALFOX_CMD[@]}")"
  log_msg INFO "Command start: Dalfox batch :: $DALFOX_LAST_CMD"
  set +e
  "${DALFOX_CMD[@]}" >"$stdout_file" 2>"$stderr_file"
  DALFOX_LAST_EXIT="$?"
  set -e
  return "$DALFOX_LAST_EXIT"
}

dalfox_run_batches() {
  local input="$1" output="$2" stderr_all="$3"
  local batch_dir batch_size batch_file stdout_file stderr_file start status duration line_count
  local batch_no=0 total_batches=0 hard_failures=0 warnings=0 reason attempt max_retries effective_workers
  : >"$output"
  : >"$stderr_all"
  batch_dir="$TMP_DIR/dalfox-batches"
  rm -rf "$batch_dir"
  mkdir -p "$batch_dir"
  batch_size="${DALFOX_BATCH_SIZE:-250}"
  if [[ ! "$batch_size" =~ ^[0-9]+$ || "$batch_size" -eq 0 ]]; then batch_size="$(count_lines "$input")"; fi
  split -l "$batch_size" -d -a 5 -- "$input" "$batch_dir/batch-"
  total_batches="$(find "$batch_dir" -type f -name 'batch-*' | wc -l | awk '{print $1}')"
  max_retries="${DALFOX_RETRIES:-1}"
  [[ "$max_retries" =~ ^[1-9][0-9]*$ ]] || max_retries=1

  for batch_file in "$batch_dir"/batch-*; do
    [[ -s "$batch_file" ]] || continue
    batch_no=$((batch_no + 1))
    line_count="$(count_lines "$batch_file")"
    attempt=1
    effective_workers="$DALFOX_WORKERS"
    while (( attempt <= max_retries )); do
      stdout_file="$(mktemp "$TMP_DIR/dalfox-stdout.XXXXXX")"
      stderr_file="$(mktemp "$TMP_DIR/dalfox-stderr.XXXXXX")"
      DALFOX_EFFECTIVE_WORKERS="$effective_workers"
      start="$(date +%s)"
      info "Running Dalfox batch $batch_no/$total_batches attempt $attempt/$max_retries ($line_count URLs, workers=$effective_workers)"
      set +e
      dalfox_run_batch_once "$batch_file" "$stdout_file" "$stderr_file" "$line_count"
      status="$?"
      set -e
      duration=$(( $(date +%s) - start ))
      log_command_result "Dalfox batch $batch_no/$total_batches attempt $attempt/$max_retries" "$status" "$duration" "$stdout_file" "$stderr_file" "${DALFOX_CMD[@]}"
      cat "$stdout_file" >>"$output"
      cat "$stderr_file" >>"$stderr_all"
      reason="$(dalfox_error_reason "$stderr_file")"
      rm -f "$stdout_file" "$stderr_file"

      if (( status == 0 )); then
        break
      fi
      if ! dalfox_is_hard_error "$reason"; then
        warnings=$((warnings + 1))
        warn "Dalfox batch $batch_no returned exit code $status with non-fatal warnings ($reason). Continuing."
        break
      fi
      warn "Dalfox batch $batch_no failed attempt $attempt/$max_retries: exit code $status ($reason)."
      if (( attempt < max_retries )) && [[ "$reason" == "too_many_open_files" && "$effective_workers" =~ ^[0-9]+$ && "$effective_workers" -gt 5 ]]; then
        effective_workers=$((effective_workers / 2))
        ((effective_workers < 5)) && effective_workers=5
        warn "Reducing Dalfox workers to $effective_workers for retry because open-file limit was hit."
      fi
      attempt=$((attempt + 1))
      sleep $((attempt < 6 ? attempt : 5))
    done
    if (( status != 0 )) && dalfox_is_hard_error "$reason"; then
      hard_failures=$((hard_failures + 1))
      DALFOX_ERROR_REASON="$reason"
    fi
  done

  DALFOX_LAST_STDERR="$stderr_all"
  if ((hard_failures > 0)); then
    DALFOX_LAST_EXIT=1
    return 1
  fi
  if ((warnings > 0)); then
    DALFOX_LAST_EXIT=0
    DALFOX_ERROR_REASON="completed_with_warnings"
  else
    DALFOX_LAST_EXIT=0
    DALFOX_ERROR_REASON="success"
  fi
  return 0
}

dalfox_text_findings_count() {
  local file="$1" poc_count summary_count
  [[ -s "$file" ]] || { printf '0'; return 0; }
  poc_count="$(awk '/^\[POC\]|\[POC\]/ {count++} END {print count + 0}' "$file" 2>/dev/null || printf '0')"
  if [[ "$poc_count" =~ ^[0-9]+$ && "$poc_count" -gt 0 ]]; then printf '%s' "$poc_count"; return 0; fi
  summary_count="$(sed -nE 's/.*XSS found[[:space:]]+([0-9]+).*/\1/p' "$file" 2>/dev/null | awk '{sum += $1} END {print sum+0}' || printf '0')"
  printf '%s' "${summary_count:-0}"
}

dalfox_findings_json_array_from_text() {
  local file="$1"
  if [[ ! -s "$file" ]]; then printf '[]'; return 0; fi
  if command_exists jq; then
    { grep -Ei '^\[POC\]|\[POC\]|XSS found[[:space:]]+[1-9]' "$file" 2>/dev/null || true; } | jq -Rsc 'split("\n") | map(select(length > 0) | {raw: .})'
  else
    printf '[]'
  fi
}

write_dalfox_normalized_json() {
  local out="$1" count="$2" status="$3" exit_code="$4" scanned="$5" skipped="$6" loaded="$7" error_file="$8" source_file="$9" reason="${10:-}"
  local command_json error_json findings_json reason_json
  command_json="$(printf '%s' "$DALFOX_LAST_CMD" | json_escape)"
  reason_json="$(printf '%s' "$reason" | json_escape)"
  if [[ -s "$error_file" ]]; then error_json="$(cat "$error_file" | json_escape)"; else error_json='""'; fi
  findings_json="$(dalfox_findings_json_array_from_text "$source_file")"
  cat >"$out" <<JSON
{
  "tool": "dalfox",
  "schema": "thor.dalfox.normalized.v2",
  "status": "$status",
  "reason": $reason_json,
  "exit_code": $exit_code,
  "findings_count": $count,
  "urls_loaded": $loaded,
  "urls_skipped": $skipped,
  "urls_scanned": $scanned,
  "command": $command_json,
  "stderr": $error_json,
  "findings": $findings_json
}
JSON
}

write_dalfox_failure_notice() {
  local out="$1" reason="$2" exit_code="$3" stderr_file="$4" count="$5"
  local tmp
  tmp="$(mktemp "$TMP_DIR/dalfox-result.XXXXXX")"
  {
    printf 'Thor Dalfox scan status: failed or incomplete.\n'
    printf 'Reason: %s\n' "$reason"
    printf 'Exit code: %s\n' "$exit_code"
    printf 'Confirmed findings parsed before/after failure: %s\n' "$count"
    printf 'Command: %s\n' "$DALFOX_LAST_CMD"
    printf '\nDalfox output follows.\n\n'
    cat "$out" 2>/dev/null || true
    printf '\nStderr follows.\n'
    if [[ -s "$stderr_file" ]]; then cat "$stderr_file"; else printf 'No stderr captured.\n'; fi
  } >"$tmp"
  mv "$tmp" "$out"
}

dalfox_live_precheck() {
  local input="$1" output="$2" unreachable="$3" httpx_bin status
  cp "$input" "$output"
  : >"$unreachable"
  if ! is_true "$DALFOX_PRECHECK_LIVE"; then return 0; fi
  if ! httpx_bin="$(resolve_httpx 2>/dev/null)"; then
    warn "Dalfox live URL precheck skipped: httpx is not installed."
    return 0
  fi
  if ! "$httpx_bin" -h 2>&1 | grep -Eq '(^|[[:space:]])-l([,[:space:]]|$)'; then
    warn "Dalfox live URL precheck skipped: installed httpx command does not support -l."
    return 0
  fi
  info "Prechecking Dalfox URLs with httpx before XSS testing."
  set +e
  "$httpx_bin" -silent -l "$input" -threads "${HTTPX_THREADS:-50}" -timeout 5 -retries 1 -o "$output" >>"$LOG_FILE" 2>&1
  status="$?"
  set -e
  if ((status != 0)); then
    warn "httpx URL precheck returned status $status; using scoped URL list without live URL reduction."
    cp "$input" "$output"
    return 0
  fi
  sort -u "$output" -o "$output"
  comm -23 <(sort -u "$input") <(sort -u "$output") | awk '{print "unreachable_or_not_httpx_live\t" $0}' >"$unreachable" || true
}

thor_module_dalfox() {
  local input="$SCAN_DIR/single_param_urls.txt" valid_input="$SCAN_DIR/dalfox_input.txt" skipped="$SCAN_DIR/dalfox_skipped_urls.txt"
  local live_input="$SCAN_DIR/dalfox_input_live.txt" unreachable="$SCAN_DIR/dalfox_unreachable_urls.txt"
  local text_out="$SCAN_DIR/dalfox_result.txt" json_out="$SCAN_DIR/dalfox_result.json" error_log="$SCAN_DIR/dalfox_error.log"
  local loaded skipped_count scanned final_count status="success" exit_code=0 reason="success" live_count unreachable_count
  : >"$text_out"; : >"$json_out"; : >"$error_log"

  if ! command_exists dalfox; then
    DALFOX_LAST_CMD="dalfox"
    printf 'Dalfox executable not found.\n' >"$error_log"
    printf 'Dalfox scan failed.\nReason: Dalfox executable not found.\n' >"$text_out"
    write_dalfox_normalized_json "$json_out" "0" "failed" "127" "0" "0" "0" "$error_log" "$text_out" "dalfox_executable_not_found"
    record_metric "dalfox_findings" "0"
    record_metric "dalfox_exit_code" "127"
    warn "Dalfox executable not found. Install with: go install github.com/hahwul/dalfox/v2@latest or use a Dalfox v3 package."
    return 0
  fi

  dalfox version >>"$LOG_FILE" 2>&1 || dalfox --version >>"$LOG_FILE" 2>&1 || true
  dalfox_raise_ulimit

  if [[ ! -e "$input" ]]; then
    printf 'Input file missing: %s\n' "$input" >"$error_log"
    printf 'Dalfox scan skipped. Input file missing: %s\n' "$input" >"$text_out"
    write_dalfox_normalized_json "$json_out" "0" "failed" "2" "0" "0" "0" "$error_log" "$text_out" "input_file_missing"
    record_metric "dalfox_findings" "0"
    return 0
  fi

  loaded="$(count_lines "$input")"
  validate_url_file_for_dalfox "$input" "$valid_input" "$skipped"
  skipped_count="$(count_lines "$skipped")"
  scanned="$(count_lines "$valid_input")"
  info "URLs Loaded: $loaded"
  info "URLs Skipped by scope/validation: $skipped_count"
  info "URLs Valid for Dalfox before live precheck: $scanned"

  if [[ "$scanned" -eq 0 ]]; then
    printf 'No valid in-scope URLs available for Dalfox scan. See %s for skipped URLs.\n' "$skipped" >"$text_out"
    write_dalfox_normalized_json "$json_out" "0" "skipped" "0" "0" "$skipped_count" "$loaded" "$error_log" "$text_out" "no_valid_urls"
    record_metric "dalfox_findings" "0"
    record_metric "dalfox_urls_loaded" "$loaded"
    record_metric "dalfox_urls_skipped" "$skipped_count"
    record_metric "dalfox_urls_scanned" "0"
    return 0
  fi

  dalfox_live_precheck "$valid_input" "$live_input" "$unreachable"
  live_count="$(count_lines "$live_input")"
  unreachable_count="$(count_lines "$unreachable")"
  skipped_count=$((skipped_count + unreachable_count))
  scanned="$live_count"
  info "URLs Skipped by live precheck: $unreachable_count"
  info "URLs Scanned by Dalfox: $scanned"

  record_metric "dalfox_urls_loaded" "$loaded"
  record_metric "dalfox_urls_skipped" "$skipped_count"
  record_metric "dalfox_urls_scanned" "$scanned"

  if [[ "$scanned" -eq 0 ]]; then
    printf 'Dalfox scan skipped. No live in-scope parameterized URLs remained after validation/precheck.\n' >"$text_out"
    write_dalfox_normalized_json "$json_out" "0" "skipped" "0" "0" "$skipped_count" "$loaded" "$error_log" "$text_out" "no_live_urls"
    record_metric "dalfox_findings" "0"
    return 0
  fi

  if dalfox_run_batches "$live_input" "$text_out" "$error_log"; then
    exit_code=0
    [[ -s "$text_out" ]] || printf 'No Dalfox findings reported.\n' >"$text_out"
    if [[ "$DALFOX_ERROR_REASON" == "completed_with_warnings" ]]; then status="completed_with_warnings"; reason="completed_with_warnings"; fi
  else
    exit_code="$DALFOX_LAST_EXIT"
    status="failed"
    reason="${DALFOX_ERROR_REASON:-dalfox_command_failed}"
  fi

  final_count="$(dalfox_text_findings_count "$text_out")"
  if [[ "$status" == "failed" ]]; then
    write_dalfox_failure_notice "$text_out" "$reason" "$exit_code" "$error_log" "$final_count"
  fi

  if is_true "$SAVE_JSON"; then
    write_dalfox_normalized_json "$json_out" "$final_count" "$status" "$exit_code" "$scanned" "$skipped_count" "$loaded" "$error_log" "$text_out" "$reason"
  fi

  record_metric "dalfox_findings" "$final_count"
  record_metric "dalfox_exit_code" "$exit_code"
  record_metric "dalfox_status" "$status"
  info "Dalfox Status: $status"
  info "Dalfox Findings: $final_count"
  info "Dalfox results saved: $text_out"
  return 0
}

register_module "dalfox" "90" "thor_module_dalfox" "Authorized scoped XSS testing with Dalfox" ""
