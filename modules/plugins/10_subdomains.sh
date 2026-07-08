#!/usr/bin/env bash
# Passive subdomain enumeration using Subfinder and Sublist3r.
# shellcheck shell=bash

thor_module_subdomains() {
  local start merged tmp_subfinder tmp_sublist3r
  start="$(date +%s)"
  tmp_subfinder="$SCAN_DIR/subfinder.txt"
  tmp_sublist3r="$SCAN_DIR/sublist3r.txt"
  merged="$SCAN_DIR/subdomains.txt"
  : >"$tmp_subfinder"
  : >"$tmp_sublist3r"

  local pids=()
  if command_exists subfinder; then
    (retry_command "subfinder $DOMAIN" subfinder -d "$DOMAIN" -silent -o "$tmp_subfinder") &
    pids+=("$!")
  else
    warn "subfinder not found; skipping subfinder. Run: thor doctor --install"
  fi

  if command_exists sublist3r; then
    (retry_command "sublist3r $DOMAIN" sublist3r -d "$DOMAIN" -o "$tmp_sublist3r") &
    pids+=("$!")
  else
    warn "sublist3r not found; skipping sublist3r. Run: thor doctor --install"
  fi

  if ((${#pids[@]} == 0)); then
    err "No passive subdomain enumerator is installed."
    return 1
  fi

  local pid status=0
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      status=1
    fi
  done
  ((status == 0)) || warn "One or more subdomain tools failed after retries; continuing with partial results."

  cat "$tmp_subfinder" "$tmp_sublist3r" 2>/dev/null >"$TMP_DIR/raw_subdomains.txt" || true
  normalize_domain_file "$TMP_DIR/raw_subdomains.txt" "$merged"
  dedup_file "$tmp_subfinder"
  dedup_file "$tmp_sublist3r"
  dedup_file "$merged"

  local count duration
  count="$(count_lines "$merged")"
  duration=$(( $(date +%s) - start ))
  record_metric "subdomains_found" "$count"
  record_metric "subdomain_enum_seconds" "$duration"
  info "Subdomains Found: $count"
  info "Subdomain Enumeration Time: $(human_time "$duration")"
  [[ "$count" -gt 0 ]]
}

register_module "subdomains" "10" "thor_module_subdomains" "Passive subdomain enumeration with Subfinder and Sublist3r" ""
