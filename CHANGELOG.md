# Changelog

All notable changes to Thor are documented here.

## [1.0.0] - 2026-07-08

### Added
- Initial public release of Thor, a Bash-based recon and Dalfox XSS automation framework for Kali Linux.
- Modular plugin architecture under `modules/plugins/`.
- Passive subdomain enumeration with Subfinder and Sublist3r.
- Optional live host validation with httpx.
- URL collection with ParamSpider, gau, waymore, and katana.
- Deduplication and strict single-parameter URL filtering.
- Scope-aware Dalfox integration with batching, live precheck, conservative workers, retry handling, and real stderr preservation.
- TXT, JSON, and dark-themed searchable HTML reports.
- Zenity/YAD GUI launcher.
- Dependency checker and optional installer.
- GitHub Actions for ShellCheck, shell syntax checks, shfmt checks, and release packaging.
- Issue templates, pull request template, security policy, contribution guide, and code of conduct.

### Security
- Removed all legacy scanner references and outdated scanner code.
- Added strict target-scope filtering before Dalfox to prevent third-party URLs from being scanned accidentally.
- Added `.env.example` for safe local overrides without committing secrets.
- Added report-integrity logic so vulnerability counts come only from normalized Dalfox findings data.

### Fixed
- Prevented `--worker`/`--workers` Dalfox flag conflicts by selecting flags from the active subcommand help.
- Prevented `Too many open files` failures by defaulting to batched scans and safer worker counts.
- Prevented conflicting reports such as “Vulnerabilities Found: 1” while Dalfox reports no findings.
