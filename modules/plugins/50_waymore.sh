#!/usr/bin/env bash
# URL collection using waymore.
# shellcheck shell=bash

thor_waymore_one() {
  local target="$1" outdir="$2" outfile="$3"
  mkdir -p "$outdir"
  if waymore --help 2>&1 | grep -q -- '-oU'; then
    retry_command "waymore $target" waymore -i "$target" -mode U -oU "$outfile" || true
  else
    retry_command_output "waymore $target" "$outfile" truncate waymore -i "$target" -mode U || true
  fi
}

thor_module_waymore() {
  local output="$SCAN_DIR/waymore.txt" input hosts target active=0 outdir tmp_out
  : >"$output"
  if ! command_exists waymore; then
    warn "waymore not found; skipping."
    return 0
  fi
  input="$SCAN_DIR/live_hosts.txt"
  [[ -s "$input" ]] || input="$SCAN_DIR/subdomains.txt"
  mapfile -t hosts < <({ printf '%s\n' "$DOMAIN"; [[ -s "$input" ]] && sed '/^$/d' "$input"; } | sed -E 's#https?://##; s#/.*##; s#:.*##' | sort -u | head -n "$MAX_URLCOLLECT_HOSTS")
  for target in "${hosts[@]}"; do
    target="$(normalize_domain "$target")"
    [[ -n "$target" ]] || continue
    outdir="$TMP_DIR/waymore_$(safe_name "$target")"
    tmp_out="$outdir/urls.txt"
    thor_waymore_one "$target" "$outdir" "$tmp_out" &
    active=$((active + 1))
    if (( active >= THREADS )); then
      wait -n || true
      active=$((active - 1))
    fi
  done
  while (( active > 0 )); do wait -n || true; active=$((active - 1)); done
  find "$TMP_DIR" -path '*waymore_*' -type f -name '*.txt' -exec cat {} + 2>/dev/null | extract_urls | filter_static_resources | sort -u >"$output" || true
  dedup_file "$output"
  record_metric "waymore_urls" "$(count_lines "$output")"
  info "Waymore URLs Found: $(count_lines "$output")"
  return 0
}

register_module "waymore" "50" "thor_module_waymore" "Historical URL collection with waymore" "ENABLE_WAYMORE"
