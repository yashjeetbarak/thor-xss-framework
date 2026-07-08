#!/usr/bin/env bash
# Report generation for Thor.
# shellcheck shell=bash

json_escape() {
  if command_exists jq; then jq -Rsa .; else python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/'; fi
}

html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"; }

json_array_from_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then printf '[]'; return 0; fi
  if command_exists jq; then jq -Rsc 'split("\n") | map(select(length > 0))' "$file"; else awk 'BEGIN{printf "["} NF{gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s\"%s\"", sep, $0; sep=","} END{printf "]"}' "$file"; fi
}

dalfox_json_value() {
  local key="$1" fallback="$2" file="$SCAN_DIR/dalfox_result.json"
  if [[ -s "$file" ]] && command_exists jq; then
    jq -r --arg key "$key" '.[$key] // empty' "$file" 2>/dev/null || printf '%s' "$fallback"
  else
    printf '%s' "$fallback"
  fi
}

report_dalfox_count() {
  local count
  count="$(dalfox_json_value "findings_count" "")"
  if [[ "$count" =~ ^[0-9]+$ ]]; then printf '%s' "$count"; return 0; fi
  dalfox_text_findings_count "$SCAN_DIR/dalfox_result.txt"
}

report_dalfox_status() {
  local status
  status="$(dalfox_json_value "status" "unknown")"
  [[ -n "$status" ]] && printf '%s' "$status" || printf 'unknown'
}

report_dalfox_reason() {
  local reason
  reason="$(dalfox_json_value "reason" "")"
  [[ -n "$reason" ]] && printf '%s' "$reason" || printf 'none'
}

report_dalfox_scanned() {
  local scanned
  scanned="$(dalfox_json_value "urls_scanned" "")"
  if [[ "$scanned" =~ ^[0-9]+$ ]]; then printf '%s' "$scanned"; return 0; fi
  count_lines "$SCAN_DIR/dalfox_input_live.txt"
}

report_counts() {
  printf '%s=%s\n' "subdomains" "$(count_lines "$SCAN_DIR/subdomains.txt")"
  printf '%s=%s\n' "live_hosts" "$(count_lines "$SCAN_DIR/live_hosts.txt")"
  printf '%s=%s\n' "all_urls" "$(count_lines "$SCAN_DIR/allparams.txt")"
  printf '%s=%s\n' "single_param_urls" "$(count_lines "$SCAN_DIR/single_param_urls.txt")"
  printf '%s=%s\n' "dalfox_urls_loaded" "$(dalfox_json_value "urls_loaded" "0")"
  printf '%s=%s\n' "dalfox_urls_skipped" "$(dalfox_json_value "urls_skipped" "0")"
  printf '%s=%s\n' "dalfox_urls_scanned" "$(report_dalfox_scanned)"
  printf '%s=%s\n' "dalfox_status" "$(report_dalfox_status)"
  printf '%s=%s\n' "dalfox_reason" "$(report_dalfox_reason)"
  printf '%s=%s\n' "vulnerabilities_found" "$(report_dalfox_count)"
}

generate_txt_report() {
  local out="$SCAN_DIR/report.txt" elapsed findings status reason
  elapsed="$(elapsed_seconds)"
  findings="$(report_dalfox_count)"
  status="$(report_dalfox_status)"
  reason="$(report_dalfox_reason)"
  {
    printf 'Thor Scan Report\n'
    printf '================\n\n'
    printf 'Target: %s\n' "$DOMAIN"
    printf 'Scan Directory: %s\n' "$SCAN_DIR"
    printf 'Generated: %s\n' "$(now_iso)"
    printf 'Elapsed: %s\n\n' "$(human_time "$elapsed")"
    printf 'Statistics\n----------\n'
    report_counts
    printf '\nDalfox Integrity\n----------------\n'
    printf 'Dalfox Status: %s\n' "$status"
    printf 'Dalfox Reason: %s\n' "$reason"
    printf 'Vulnerabilities Found: %s\n' "$findings"
    if [[ "$status" == "failed" ]]; then
      printf 'Note: The Dalfox stage did not complete cleanly. Treat this scan as incomplete even if findings_count is 0.\n'
    fi
    printf '\nFiles\n-----\n'
    printf 'Subdomains: %s\n' "$SCAN_DIR/subdomains.txt"
    printf 'Live Hosts: %s\n' "$SCAN_DIR/live_hosts.txt"
    printf 'All URLs: %s\n' "$SCAN_DIR/allparams.txt"
    printf 'Single Parameter URLs: %s\n' "$SCAN_DIR/single_param_urls.txt"
    printf 'Dalfox Input: %s\n' "$SCAN_DIR/dalfox_input.txt"
    printf 'Dalfox Live Input: %s\n' "$SCAN_DIR/dalfox_input_live.txt"
    printf 'Dalfox Skipped URLs: %s\n' "$SCAN_DIR/dalfox_skipped_urls.txt"
    printf 'Dalfox Unreachable URLs: %s\n' "$SCAN_DIR/dalfox_unreachable_urls.txt"
    printf 'Dalfox TXT: %s\n' "$SCAN_DIR/dalfox_result.txt"
    printf 'Dalfox JSON: %s\n' "$SCAN_DIR/dalfox_result.json"
    printf 'Dalfox Errors: %s\n\n' "$SCAN_DIR/dalfox_error.log"
    printf 'Dalfox Findings Preview\n-----------------------\n'
    if [[ -s "$SCAN_DIR/dalfox_result.txt" ]]; then
      grep -Ei '^\[POC\]|\[POC\]|XSS found[[:space:]]+[1-9]' "$SCAN_DIR/dalfox_result.txt" | head -n 100 || printf 'No Dalfox findings reported.\n'
    else
      printf 'No Dalfox findings file or empty output.\n'
    fi
  } >"$out"
}

generate_json_report() {
  local out="$SCAN_DIR/report.json" elapsed findings status reason
  elapsed="$(elapsed_seconds)"
  findings="$(report_dalfox_count)"
  status="$(report_dalfox_status)"
  reason="$(report_dalfox_reason)"
  cat >"$out" <<JSON
{
  "tool": "Thor",
  "version": "$THOR_VERSION",
  "target": $(printf '%s' "$DOMAIN" | json_escape),
  "scan_dir": $(printf '%s' "$SCAN_DIR" | json_escape),
  "generated_at": "$(now_iso)",
  "elapsed_seconds": $elapsed,
  "integrity": {
    "dalfox_status": $(printf '%s' "$status" | json_escape),
    "dalfox_reason": $(printf '%s' "$reason" | json_escape),
    "counts_source": "dalfox_result.json.findings_count"
  },
  "statistics": {
    "subdomains": $(count_lines "$SCAN_DIR/subdomains.txt"),
    "live_hosts": $(count_lines "$SCAN_DIR/live_hosts.txt"),
    "all_urls": $(count_lines "$SCAN_DIR/allparams.txt"),
    "single_param_urls": $(count_lines "$SCAN_DIR/single_param_urls.txt"),
    "dalfox_urls_loaded": $(dalfox_json_value "urls_loaded" "0"),
    "dalfox_urls_skipped": $(dalfox_json_value "urls_skipped" "0"),
    "dalfox_urls_scanned": $(report_dalfox_scanned),
    "vulnerabilities_found": $findings
  },
  "subdomains": $(json_array_from_file "$SCAN_DIR/subdomains.txt"),
  "live_hosts": $(json_array_from_file "$SCAN_DIR/live_hosts.txt"),
  "single_param_urls": $(json_array_from_file "$SCAN_DIR/single_param_urls.txt"),
  "dalfox_text": $(json_array_from_file "$SCAN_DIR/dalfox_result.txt")
}
JSON
}

html_table_from_file() {
  local file="$1" limit="${2:-500}"
  if [[ ! -s "$file" ]]; then printf '<tr><td class="muted">No data</td></tr>\n'; return 0; fi
  head -n "$limit" "$file" | html_escape | awk '{printf "<tr><td><code>%s</code></td></tr>\n", $0}'
}

generate_html_report() {
  local out="$SCAN_DIR/report.html" elapsed sub live all single scanned skipped findings max=1 item local_name local_val width status reason status_class
  elapsed="$(elapsed_seconds)"
  sub="$(count_lines "$SCAN_DIR/subdomains.txt")"
  live="$(count_lines "$SCAN_DIR/live_hosts.txt")"
  all="$(count_lines "$SCAN_DIR/allparams.txt")"
  single="$(count_lines "$SCAN_DIR/single_param_urls.txt")"
  scanned="$(report_dalfox_scanned)"
  skipped="$(dalfox_json_value "urls_skipped" "0")"
  findings="$(report_dalfox_count)"
  status="$(report_dalfox_status)"
  reason="$(report_dalfox_reason)"
  status_class="ok"
  [[ "$status" == "failed" ]] && status_class="bad"
  [[ "$status" == "completed_with_warnings" || "$status" == "skipped" ]] && status_class="warn"
  for n in "$sub" "$live" "$all" "$single" "$scanned" "$skipped" "$findings"; do (( n > max )) && max="$n"; done
  cat >"$out" <<HTML_HEAD
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Thor Report - $(printf '%s' "$DOMAIN" | html_escape)</title>
  <style>
    :root { --bg:#070b14; --panel:#101827; --panel2:#17233a; --text:#e7edf7; --muted:#95a8c7; --brand:#38bdf8; --accent:#f59e0b; --bad:#fb7185; --ok:#34d399; --warn:#fbbf24; }
    * { box-sizing:border-box; }
    body { margin:0; font-family:Inter, ui-sans-serif, system-ui, -apple-system, Segoe UI, Arial, sans-serif; background:radial-gradient(circle at top left,#172554 0,#070b14 38%,#020617 100%); color:var(--text); }
    header { padding:38px 24px; border-bottom:1px solid #24324d; background:linear-gradient(135deg,#0f172a99,#111827cc); position:sticky; top:0; backdrop-filter: blur(12px); z-index:2; }
    h1 { margin:0; font-size:48px; letter-spacing:-.06em; }
    h2 { margin-top:34px; }
    .tagline,.muted { color:var(--muted); }
    .wrap { max-width:1220px; margin:auto; padding:24px; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:16px; }
    .card { background:linear-gradient(180deg,#111827,#0f172a); border:1px solid #24324d; border-radius:20px; padding:18px; box-shadow:0 10px 40px #0006; }
    .num { font-size:34px; font-weight:900; }
    .bar { height:10px; background:#25324d; border-radius:999px; overflow:hidden; margin-top:12px; }
    .bar span { display:block; height:100%; background:linear-gradient(90deg,var(--brand),var(--accent)); }
    .toolbar { display:flex; gap:12px; flex-wrap:wrap; align-items:center; margin:18px 0; }
    input,button { border-radius:12px; border:1px solid #334155; background:#0f172a; color:var(--text); padding:11px 14px; }
    button { cursor:pointer; background:var(--panel2); }
    table { width:100%; border-collapse:collapse; background:var(--panel); border-radius:16px; overflow:hidden; }
    td,th { padding:10px 12px; border-bottom:1px solid #263653; vertical-align:top; }
    code { color:#bae6fd; word-break:break-all; }
    .pill { display:inline-flex; padding:6px 11px; background:#1f2937; border:1px solid #334155; border-radius:999px; color:var(--muted); margin:4px 6px 4px 0; }
    .ok { color:var(--ok); } .bad { color:var(--bad); } .warn { color:var(--warn); }
    .statusbox { border-left:4px solid var(--brand); }
    .statusbox.bad { border-left-color:var(--bad); } .statusbox.warn { border-left-color:var(--warn); }
    footer { color:var(--muted); padding:40px 0; }
  </style>
</head>
<body>
<header><div class="wrap"><h1>⚡ Thor</h1><p class="tagline">The Automated Recon &amp; XSS Hunting Framework</p><p><span class="pill">Target: $(printf '%s' "$DOMAIN" | html_escape)</span><span class="pill">Generated: $(now_iso)</span><span class="pill">Elapsed: $(human_time "$elapsed")</span><span class="pill $status_class">Dalfox: $(printf '%s' "$status" | html_escape)</span></p></div></header>
<main class="wrap">
  <section class="grid">
HTML_HEAD
  for item in "Subdomains:$sub" "Live Hosts:$live" "URLs:$all" "Single Param URLs:$single" "Dalfox URLs Scanned:$scanned" "Skipped:$skipped" "Vulnerabilities Found:$findings"; do
    local_name="${item%%:*}"; local_val="${item##*:}"; width=$(( local_val * 100 / max ))
    cat >>"$out" <<HTML_CARD
    <div class="card"><div class="muted">$local_name</div><div class="num">$local_val</div><div class="bar"><span style="width:${width}%"></span></div></div>
HTML_CARD
  done
  cat >>"$out" <<HTML_MID
  </section>
  <section class="card statusbox $status_class" style="margin-top:20px">
    <h2>Scan Integrity</h2>
    <p><strong>Dalfox status:</strong> <span class="$status_class">$(printf '%s' "$status" | html_escape)</span></p>
    <p><strong>Reason:</strong> <code>$(printf '%s' "$reason" | html_escape)</code></p>
    <p class="muted">The vulnerability count is read from <code>dalfox_result.json.findings_count</code>. The report does not count generic words like “XSS” from error messages.</p>
    <div class="toolbar"><input id="q" placeholder="Search report…" oninput="filterRows()"><button onclick="window.print()">Export / Print</button><button onclick="downloadJSON()">Export JSON</button></div>
  </section>
HTML_MID
  {
    printf '<section><h2>Subdomains</h2><table class="filterable"><tbody>\n'; html_table_from_file "$SCAN_DIR/subdomains.txt" 1000; printf '</tbody></table></section>\n'
    printf '<section><h2>Live Hosts</h2><table class="filterable"><tbody>\n'; html_table_from_file "$SCAN_DIR/live_hosts.txt" 1000; printf '</tbody></table></section>\n'
    printf '<section><h2>Dalfox Scoped Input</h2><table class="filterable"><tbody>\n'; html_table_from_file "$SCAN_DIR/dalfox_input_live.txt" 2000; printf '</tbody></table></section>\n'
    printf '<section><h2>Dalfox Skipped URLs</h2><table class="filterable"><tbody>\n'; html_table_from_file "$SCAN_DIR/dalfox_skipped_urls.txt" 2000; printf '</tbody></table></section>\n'
    printf '<section><h2>Dalfox Findings / Output</h2><table class="filterable"><tbody>\n'; html_table_from_file "$SCAN_DIR/dalfox_result.txt" 2000; printf '</tbody></table></section>\n'
  } >>"$out"
  cat >>"$out" <<'HTML_END'
</main>
<footer class="wrap">Thor is intended only for educational purposes and authorized assessments.</footer>
<script>
function filterRows(){const q=document.getElementById('q').value.toLowerCase();document.querySelectorAll('.filterable tr').forEach(r=>{r.style.display=r.innerText.toLowerCase().includes(q)?'':'none'});}
function downloadJSON(){fetch('report.json').then(r=>r.text()).then(t=>{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([t],{type:'application/json'}));a.download='thor-report.json';a.click();});}
</script>
</body></html>
HTML_END
}

generate_reports() {
  [[ -n "${SCAN_DIR:-}" && -d "$SCAN_DIR" ]] || { err "SCAN_DIR is not set."; return 1; }
  generate_txt_report
  generate_json_report
  if is_true "$SAVE_HTML"; then generate_html_report; fi
  info "Reports generated in $SCAN_DIR"
}
