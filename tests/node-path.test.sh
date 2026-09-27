#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/install.sh"
fix_script="$root/scripts/fix-node-path.sh"

require() {
  local pattern="$1" file="$2" description="$3"
  if ! grep -qF -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    exit 1
  fi
}

require 'fix-node-path.sh' "$installer" 'install.sh refreshes node symlinks after nvm setup'
require 'ln -sf' "$fix_script" 'fix-node-path.sh links node binaries into LOCAL_BIN'
require 'node npm npx' "$fix_script" 'fix-node-path covers node, npm and npx'
require 'command -v node' "$fix_script" 'fix script proves node resolves with minimal PATH'

# node must never be pinned to one nvm version dir in NEW code paths
if grep -n 'versions/node/v[0-9]' "$fix_script" >/dev/null; then
  printf 'FAIL: fix-node-path.sh pins a concrete nvm version\n' >&2
  exit 1
fi

printf 'PASS: stable node path (agentation-style MCP spawn safe)\n'
