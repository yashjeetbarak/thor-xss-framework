#!/usr/bin/env bash
# Plugin registry for Thor.
# shellcheck shell=bash

set -Eeuo pipefail
IFS=$'\n\t'

declare -ag THOR_MODULES=()
declare -Ag THOR_MODULE_ORDER=()
declare -Ag THOR_MODULE_FUNC=()
declare -Ag THOR_MODULE_DESC=()
declare -Ag THOR_MODULE_ENABLED_VAR=()

register_module() {
  local name="$1" order="$2" func="$3" desc="$4" enabled_var="${5:-}"
  THOR_MODULES+=("$name")
  THOR_MODULE_ORDER["$name"]="$order"
  THOR_MODULE_FUNC["$name"]="$func"
  THOR_MODULE_DESC["$name"]="$desc"
  THOR_MODULE_ENABLED_VAR["$name"]="$enabled_var"
}

load_plugins() {
  local plugin
  for plugin in "$THOR_ROOT"/modules/plugins/*.sh; do
    [[ -f "$plugin" ]] || continue
    # shellcheck disable=SC1090
    source "$plugin"
  done
}

module_enabled() {
  local name="$1" var="${THOR_MODULE_ENABLED_VAR[$name]:-}"
  [[ -z "$var" ]] && return 0
  is_true "${!var:-false}"
}

ordered_modules() {
  local name
  for name in "${THOR_MODULES[@]}"; do printf '%s\t%s\n' "${THOR_MODULE_ORDER[$name]}" "$name"; done | sort -n | cut -f2-
}

run_pipeline() {
  local name func start duration subs urls done_count=0 total=0
  local -a ordered=()
  mapfile -t ordered < <(ordered_modules)
  total="${#ordered[@]}"
  TOTAL_STEPS="$total"
  for name in "${ordered[@]}"; do
    if ! module_enabled "$name"; then
      warn "Skipping disabled module: $name"
      done_count=$((done_count + 1))
      continue
    fi
    func="${THOR_MODULE_FUNC[$name]}"
    CURRENT_STEP="$name"
    subs="$(count_lines "$SCAN_DIR/subdomains.txt")"
    urls="$(count_lines "$SCAN_DIR/allparams.txt")"
    progress_line "$name" "$DOMAIN" "$done_count" "$total" "$urls" "$subs"
    if step_done "$name"; then
      log_msg INFO "Resume: skipping completed module $name"
      done_count=$((done_count + 1))
      continue
    fi
    start="$(date +%s)"
    info "Starting module: $name - ${THOR_MODULE_DESC[$name]}"
    if "$func"; then
      duration=$(( $(date +%s) - start ))
      mark_step_done "$name" "$duration"
      info "Completed module: $name (${duration}s)"
    else
      duration=$(( $(date +%s) - start ))
      warn "Module failed or produced no output: $name (${duration}s). Continuing where safe."
      mark_step_done "$name" "$duration"
    fi
    done_count=$((done_count + 1))
    subs="$(count_lines "$SCAN_DIR/subdomains.txt")"
    urls="$(count_lines "$SCAN_DIR/allparams.txt")"
    progress_line "$name" "$DOMAIN" "$done_count" "$total" "$urls" "$subs"
  done
  progress_done
}
