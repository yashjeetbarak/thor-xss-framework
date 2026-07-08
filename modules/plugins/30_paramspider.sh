#!/usr/bin/env bash
# Parameter discovery using ParamSpider.
# shellcheck shell=bash

thor_paramspider_one() {
  local host="$1"
  local clean out tmp_run stdout generated
  clean="$(normalize_domain "$host")"
  [[ -n "$clean" ]] || return 0
  out="$SCAN_DIR/paramspider/$(safe_name "$clean").txt"
  tmp_run="$(mktemp -d "$TMP_DIR/paramspider.XXXXXX")"
  stdout="$tmp_run/stdout.txt"
  : >"$out"

  if ! command_exists paramspider; then
    warn "paramspider not found; skipping ParamSpider module."
    rm -rf "$tmp_run"
    return 1
  fi

  if paramspider --help 2>&1 | grep -Eq '(^|[[:space:]])(-o|--output)(,|[[:space:]])'; then
    retry_command "ParamSpider $clean" paramspider -d "$clean" -o "$out" || true
  else
    (
      cd "$tmp_run"
      retry_command_output "ParamSpider $clean" "$stdout" truncate paramspider -d "$clean" || true
    )
    generated="$(find "$tmp_run" -type f \( -name '*.txt' -o -name '*.log' \) -print | tr '\n' ' ')"
    # shellcheck disable=SC2086
    cat $generated 2>/dev/null | extract_urls >>"$out" || true
    extract_urls <"$stdout" >>"$out" || true
  fi

  if [[ -s "$out" ]]; then
    sed -i 's/FUZZ/123/g' "$out"
    dedup_file "$out"
  fi
  rm -rf "$tmp_run"
}

thor_module_paramspider() {
  local input host active=0 total=0 done_count=0
  input="$SCAN_DIR/live_hosts.txt"
  [[ -s "$input" ]] || input="$SCAN_DIR/subdomains.txt"
  if [[ ! -s "$input" ]]; then
    warn "No hosts available for ParamSpider."
    return 1
  fi
  mkdir -p "$SCAN_DIR/paramspider"
  mapfile -t hosts < <(sed '/^$/d' "$input" | head -n "$MAX_URLCOLLECT_HOSTS")
  total="${#hosts[@]}"
  ((total > 0)) || return 1

  for host in "${hosts[@]}"; do
    thor_paramspider_one "$host" &
    active=$((active + 1))
    if (( active >= PARAMSPIDER_THREADS )); then
      wait -n || true
      active=$((active - 1))
      done_count=$((done_count + 1))
      progress_line "paramspider" "$host" "$done_count" "$total" "0" "$(count_lines "$SCAN_DIR/subdomains.txt")"
    fi
  done
  while (( active > 0 )); do
    wait -n || true
    active=$((active - 1))
    done_count=$((done_count + 1))
  done
  progress_done

  find "$SCAN_DIR/paramspider" -type f -name '*.txt' -size +0c -exec awk 'NF {print}' {} + >"$TMP_DIR/paramspider_all.txt" 2>/dev/null || true
  sort -u "$TMP_DIR/paramspider_all.txt" >"$SCAN_DIR/paramspider.txt" 2>/dev/null || : >"$SCAN_DIR/paramspider.txt"
  dedup_file "$SCAN_DIR/paramspider.txt"
  record_metric "paramspider_urls" "$(count_lines "$SCAN_DIR/paramspider.txt")"
  info "ParamSpider URLs Found: $(count_lines "$SCAN_DIR/paramspider.txt")"
  return 0
}

register_module "paramspider" "30" "thor_module_paramspider" "Parameter discovery with ParamSpider" "ENABLE_PARAMSPIDER"
