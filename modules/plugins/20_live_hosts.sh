#!/usr/bin/env bash
# Live host detection using ProjectDiscovery httpx.
# shellcheck shell=bash

thor_module_live_hosts() {
  local input="$SCAN_DIR/subdomains.txt"
  local output="$SCAN_DIR/live_hosts.txt"
  : >"$output"

  if [[ ! -s "$input" ]]; then
    warn "No subdomains available for live host detection."
    return 1
  fi

  if ! is_true "$ENABLE_HTTPX"; then
    cp "$input" "$output"
    dedup_file "$output"
    record_metric "live_hosts_found" "$(count_lines "$output")"
    info "HTTPX disabled; using subdomains.txt as live_hosts.txt"
    return 0
  fi

  local httpx_bin
  if ! httpx_bin="$(resolve_httpx)"; then
    warn "httpx/httpx-toolkit not found; using subdomains.txt instead."
    cp "$input" "$output"
    dedup_file "$output"
    record_metric "live_hosts_found" "$(count_lines "$output")"
    return 0
  fi

  retry_command "httpx live host detection" "$httpx_bin" -l "$input" -silent -threads "$HTTPX_THREADS" -o "$output" || {
    warn "httpx failed after retries; falling back to subdomains.txt"
    cp "$input" "$output"
  }
  dedup_file "$output"
  record_metric "live_hosts_found" "$(count_lines "$output")"
  info "Live Hosts Found: $(count_lines "$output")"
  [[ -s "$output" ]]
}

register_module "live_hosts" "20" "thor_module_live_hosts" "Live host detection with httpx or fallback to subdomains" ""
