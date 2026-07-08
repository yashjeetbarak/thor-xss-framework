#!/usr/bin/env bash
# Filter to single-parameter candidate URLs for Dalfox.
# shellcheck shell=bash

thor_module_filter_urls() {
  local input="$SCAN_DIR/allparams.txt" output="$SCAN_DIR/single_param_urls.txt" skipped="$SCAN_DIR/single_param_urls.skipped.txt" raw_count valid_count skipped_count
  : >"$output"
  : >"$skipped"
  [[ -s "$input" ]] || { warn "No URLs to filter."; return 1; }

  extract_urls <"$input" | sed 's/FUZZ/123/g' | filter_static_resources | sort -u >"$TMP_DIR/single_param_candidates.txt" || true
  raw_count="$(count_lines "$TMP_DIR/single_param_candidates.txt")"
  validate_url_file_for_dalfox "$TMP_DIR/single_param_candidates.txt" "$output" "$skipped"
  dedup_file "$output"
  valid_count="$(count_lines "$output")"
  skipped_count="$(count_lines "$skipped")"

  record_metric "single_param_urls_loaded" "$raw_count"
  record_metric "single_param_urls_skipped" "$skipped_count"
  record_metric "single_param_urls" "$valid_count"
  info "URLs Loaded for Dalfox filtering: $raw_count"
  info "URLs Skipped before Dalfox: $skipped_count"
  info "Single Parameter URLs Found: $valid_count"
  [[ "$valid_count" -gt 0 ]]
}

register_module "filter_urls" "80" "thor_module_filter_urls" "Filter and validate URL candidates for XSS testing" ""
