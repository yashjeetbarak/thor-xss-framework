#!/usr/bin/env bash
# URL collection using gau.
# shellcheck shell=bash

thor_gau_one() {
  local host="$1" clean="$2" out="$3"
  if gau --help 2>&1 | grep -q -- '--threads'; then
    retry_command_output "gau $clean" "$out" append gau --threads "$THREADS" "$clean" || true
  else
    retry_command_output "gau $clean" "$out" append gau "$clean" || true
  fi
}

thor_module_gau() {
  local output="$SCAN_DIR/gau.txt" input hosts clean active=0
  : >"$output"
  if ! command_exists gau; then
    warn "gau not found; skipping."
    return 0
  fi
  input="$SCAN_DIR/live_hosts.txt"
  [[ -s "$input" ]] || input="$SCAN_DIR/subdomains.txt"
  [[ -s "$input" ]] || return 0
  mapfile -t hosts < <({ printf '%s\n' "$DOMAIN"; sed '/^$/d' "$input"; } | sed -E 's#https?://##; s#/.*##; s#:.*##' | sort -u | head -n "$MAX_URLCOLLECT_HOSTS")
  for host in "${hosts[@]}"; do
    clean="$(normalize_domain "$host")"
    [[ -n "$clean" ]] || continue
    thor_gau_one "$host" "$clean" "$output" &
    active=$((active + 1))
    if (( active >= THREADS )); then
      wait -n || true
      active=$((active - 1))
    fi
  done
  while (( active > 0 )); do wait -n || true; active=$((active - 1)); done
  extract_urls <"$output" | filter_static_resources | sort -u >"$TMP_DIR/gau.clean.txt" || true
  mv "$TMP_DIR/gau.clean.txt" "$output"
  dedup_file "$output"
  record_metric "gau_urls" "$(count_lines "$output")"
  info "GAU URLs Found: $(count_lines "$output")"
  return 0
}

register_module "gau" "40" "thor_module_gau" "Historical URL collection with gau" "ENABLE_GAU"
