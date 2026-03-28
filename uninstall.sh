#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

remove_if_matches() {
  local path="$1"
  local target="$2"

  if [[ -L "${path}" ]] && [[ "$(readlink "${path}")" == "${target}" ]]; then
    rm "${path}"
    echo "removed ${path}"
  fi
}

remove_if_matches "${HOME}/.local/bin/ralph-codex" "${ROOT_DIR}/bin/ralph-codex"
remove_if_matches "${HOME}/.agents/skills/prd" "${ROOT_DIR}/skills/prd"
remove_if_matches "${HOME}/.agents/skills/ralph" "${ROOT_DIR}/skills/ralph"

echo "Uninstalled ralph-codex."
