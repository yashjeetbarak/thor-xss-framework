#!/usr/bin/env bash
# URL discovery using ProjectDiscovery katana.
# shellcheck shell=bash

thor_module_katana() {
  local input="$SCAN_DIR/live_hosts.txt" output="$SCAN_DIR/katana.txt" list="$TMP_DIR/katana_targets.txt"
  : >"$output"
  if ! command_exists katana; then
    warn "katana not found; skipping."
    return 0
  fi
  [[ -s "$input" ]] || input="$SCAN_DIR/subdomains.txt"
  [[ -s "$input" ]] || return 0
  sed '/^$/d' "$input" | head -n "$MAX_URLCOLLECT_HOSTS" >"$list"
  local cmd=(katana -list "$list" -silent -d "$KATANA_DEPTH" -c "$KATANA_CONCURRENCY" -o "$output")
  if katana --help 2>&1 | grep -q -- '-jc'; then
    cmd+=( -jc )
  fi
  retry_command "katana crawl" "${cmd[@]}" || true
  extract_urls <"$output" | filter_static_resources | sort -u >"$TMP_DIR/katana.clean.txt" || true
  mv "$TMP_DIR/katana.clean.txt" "$output"
  dedup_file "$output"
  record_metric "katana_urls" "$(count_lines "$output")"
  info "Katana URLs Found: $(count_lines "$output")"
  return 0
}

register_module "katana" "60" "thor_module_katana" "Crawl live hosts with katana" "ENABLE_KATANA"
