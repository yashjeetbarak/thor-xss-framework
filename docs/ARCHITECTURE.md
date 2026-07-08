# Thor Architecture

Thor is intentionally small at the core and extensible through plugins.

## Core files

- `thor.sh` parses CLI commands, initializes scans, and calls the pipeline.
- `modules/lib/common.sh` provides configuration, logging, state, validation, and shared helpers.
- `modules/registry.sh` loads plugins and runs them in registered order.
- `modules/reporting.sh` generates TXT, JSON, and HTML reports.
- `modules/dependencies.sh` checks and optionally installs external CLI tools.

## Plugin contract

A plugin should:

1. Define a function that performs one stage.
2. Use shared helpers for logging and command execution.
3. Write outputs into `$SCAN_DIR`.
4. Deduplicate outputs where appropriate.
5. Register itself with `register_module`.

Example:

```bash
thor_module_example() {
  info "Running example module"
  # module logic here
}

register_module "example" "99" "thor_module_example" "Example module description" "ENABLE_EXAMPLE"
```

## Safety design

The Dalfox stage validates and scopes URLs before active testing. It rejects third-party hosts, malformed URLs, multi-parameter URLs, unsupported protocols, static files, and non-live hosts when live host data is available.
