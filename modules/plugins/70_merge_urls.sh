#!/usr/bin/env bash
# Merge URL sources into allparams.txt.
# shellcheck shell=bash

thor_module_merge_urls() {
  local output="$SCAN_DIR/allparams.txt"
  : >"$output"
  find "$SCAN_DIR/paramspider" -type f -name '*.txt' -size +0c -exec cat {} + 2>/dev/null >>"$output" || true
  for f in "$SCAN_DIR/paramspider.txt" "$SCAN_DIR/gau.txt" "$SCAN_DIR/waymore.txt" "$SCAN_DIR/katana.txt"; do
    [[ -f "$f" ]] && cat "$f" >>"$output"
  done
  extract_urls <"$output" | sed 's/FUZZ/123/g' | filter_static_resources | sort -u >"$TMP_DIR/allparams.clean.txt" || true
  mv "$TMP_DIR/allparams.clean.txt" "$output"
  dedup_file "$output"
  record_metric "all_urls" "$(count_lines "$output")"
  info "All URLs Found: $(count_lines "$output")"
  [[ -s "$output" ]]
}

register_module "merge_urls" "70" "thor_module_merge_urls" "Merge and deduplicate URL collections" ""
