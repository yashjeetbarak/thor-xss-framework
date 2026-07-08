# Thor Audit Report — Dalfox Reliability Build

## Root causes fixed

1. **Open-file exhaustion**
   The previous Dalfox command used high worker concurrency and Dalfox's own output writer against thousands of URLs. The real failure was `Too many open files (os error 24)`. Thor now uses conservative workers, raises `ulimit` where possible, splits input into batches, and captures stdout/stderr itself instead of relying on the Dalfox `--output` writer for the primary text result.

2. **Out-of-scope URL pollution**
   URL collectors returned third-party URLs such as analytics, video, banking, font, and social domains. Thor now rejects every URL whose host is not the target domain or one of its subdomains.

3. **Dead host and unreachable URL noise**
   Dalfox was spending time on dead URLs. Thor now filters by live hosts when `live_hosts.txt` exists and can optionally run a URL-level httpx precheck before Dalfox.

4. **Invalid parameter candidates**
   Values like `?logout`, `?C=D;O=A`, multi-parameter URLs, malformed URLs, static assets, and unsupported protocols are rejected before Dalfox.

5. **Flag mismatch across Dalfox versions**
   Dalfox v3 file mode uses `--workers`, while some older versions use different flags. Thor now reads the selected subcommand's help and chooses `--workers`, `--worker`, or `-w` only if supported.

6. **Contradictory report counts**
   Reports no longer count generic words such as `XSS` in failure messages. The source of truth is `dalfox_result.json.findings_count`.

## Files audited and changed

- `thor.sh`
- `config.conf`
- `modules/lib/common.sh`
- `modules/plugins/80_filter_urls.sh`
- `modules/plugins/90_dalfox.sh`
- `modules/reporting.sh`
- `README.md`
- `CHANGELOG.md`

## New Dalfox controls

```conf
DALFOX_WORKERS="25"
DALFOX_TIMEOUT="8"
DALFOX_RETRIES="1"
DALFOX_BATCH_SIZE="250"
DALFOX_PRECHECK_LIVE="true"
DALFOX_REQUIRE_LIVE_HOSTS="true"
DALFOX_SCOPE_ONLY="true"
DALFOX_MAX_TARGETS_PER_HOST="0"
DALFOX_ULIMIT="8192"
DALFOX_USE_OUTPUT_FLAG="false"
```

## Verification performed

- Bash syntax checked for every `.sh` file.
- Repository searched for legacy scanner references.
- Simulated Dalfox v3.1.2 file mode with `--workers` was tested.
- Verified Thor does not pass `--worker` to a v3 file-mode Dalfox binary.
- Verified Thor does not pass `--output` by default for the primary text scan.
- Verified out-of-scope and static URLs are rejected.
- Verified `report.txt`, `report.json`, `report.html`, and `dalfox_result.json` share one finding count.

## Operational guidance

For large targets, keep `DALFOX_WORKERS` between `15` and `30`. Increase only after confirming open-file limits and target stability. If a scan is slow, reduce URL collectors or keep the live precheck enabled.
