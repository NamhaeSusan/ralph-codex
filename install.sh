#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
SKILLS_DIR="${HOME}/.agents/skills"

mkdir -p "${BIN_DIR}" "${SKILLS_DIR}"
chmod +x "${ROOT_DIR}/bin/ralph-codex"

ln -sfn "${ROOT_DIR}/bin/ralph-codex" "${BIN_DIR}/ralph-codex"
ln -sfn "${ROOT_DIR}/skills/prd" "${SKILLS_DIR}/prd"
ln -sfn "${ROOT_DIR}/skills/ralph" "${SKILLS_DIR}/ralph"

echo "Installed ralph-codex from ${ROOT_DIR}"
echo "Restart Codex to discover the prd and ralph skills."
