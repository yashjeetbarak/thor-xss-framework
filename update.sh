#!/usr/bin/env bash
# Update Thor and optionally its external tools.
# shellcheck shell=bash

set -Eeuo pipefail
IFS=$'\n\t'
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

if [[ -d "$ROOT/.git" ]]; then
  git -C "$ROOT" pull --ff-only
else
  printf 'Not a git checkout. Replace this directory with a new release archive to update Thor.\n' >&2
fi

read -r -p 'Update external tools too? [y/N] ' ans || ans=""
if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then "$ROOT/thor.sh" doctor --install; fi
