# Contributing to Thor

Thank you for helping improve Thor.

## Rules of Engagement

Thor is for educational use and authorized security assessments only. Contributions that add stealth, bypass, credential theft, destructive behavior, unauthorized exploitation, or persistence will not be accepted.

## Development Setup

```bash
git clone <your Thor fork URL>
cd thor
./install.sh
thor doctor
```

## Code Style

- Bash 5 compatible.
- Use `set -Eeuo pipefail` in executable scripts.
- Quote variables.
- Never use `eval`.
- Use arrays for commands.
- Use `mktemp` for temporary files.
- Keep modules independent.
- Deduplicate generated outputs.

Run:

```bash
shellcheck thor.sh install.sh update.sh uninstall.sh gui/*.sh modules/**/*.sh
shfmt -w thor.sh install.sh update.sh uninstall.sh gui/*.sh modules/**/*.sh
```

## Adding a Plugin

Create a new file under `modules/plugins`:

```bash
#!/usr/bin/env bash
# shellcheck shell=bash

thor_module_example() {
  # read input from $SCAN_DIR
  # write output to $SCAN_DIR
  # use retry_command for external commands
  return 0
}

register_module "example" "75" "thor_module_example" "Example plugin" "ENABLE_EXAMPLE"
```

Add configuration defaults to `config.conf`, document the module in `README.md`, and include safe tests or dry-run behavior where possible.

## Pull Request Checklist

- [ ] The feature is appropriate for authorized testing.
- [ ] ShellCheck passes.
- [ ] shfmt applied.
- [ ] README/config updated.
- [ ] No secrets or target data included.
- [ ] No generated results committed.
