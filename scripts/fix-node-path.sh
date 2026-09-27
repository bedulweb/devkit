#!/usr/bin/env bash
# fix-node-path.sh — stable node/npm/npx on PATH for EVERY context.
#
# Root cause it fixes: node lives in nvm's versioned dir
# (~/.nvm/versions/node/v<ver>/bin), which is only on PATH in interactive
# shells. Anything spawned non-interactively (systemd units, opencode MCP
# servers like agentation, cron, doppler run) then fails with
# `node: command not found` — and absolute baked-in paths go stale on every
# node upgrade. This script symlinks node/npm/npx/corepack into ~/.local/bin
# (which is already FIRST on PATH in .bashrc, .linux-devkit/env and all
# systemd units), so resolution is permanent across version bumps.
#
#   bash ~/linux-devkit/scripts/fix-node-path.sh
# Idempotent: safe to re-run (also called by install.sh after nvm setup).
set -euo pipefail

LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"

log() { printf '==> %s\n' "$*"; }
ok()  { printf '  ✓ %s\n' "$*"; }
die() { printf '  ✗ %s\n' "$*" >&2; exit 1; }

# resolve the active nvm node bin dir (explicit version > default alias > newest)
node_bin_dir() {
  local dir=""
  if command -v nvm >/dev/null 2>&1; then
    dir="$(nvm which default 2>/dev/null | xargs dirname 2>/dev/null || true)"
  fi
  if [[ -z "$dir" || ! -x "$dir/node" ]]; then
    dir="$(ls -d "$HOME"/.nvm/versions/node/v*/bin 2>/dev/null | sort -V | tail -1 || true)"
  fi
  [[ -n "$dir" && -x "$dir/node" ]] && printf '%s' "$dir" || return 1
}

main() {
  local bindir
  bindir="$(node_bin_dir)" || die "no nvm node found (run install.sh first)"
  log "node source → $bindir"
  mkdir -p "$LOCAL_BIN"
  local linked=0
  for tool in node npm npx corepack; do
    if [[ -x "$bindir/$tool" ]]; then
      ln -sf "$bindir/$tool" "$LOCAL_BIN/$tool"
      ok "$tool → $(readlink "$LOCAL_BIN/$tool")"
      linked=1
    fi
  done
  [[ "$linked" == "1" ]] || die "nothing to link in $bindir"
  # prove it resolves with a bare non-interactive PATH (MCP-spawn simulation)
  env -i "PATH=$LOCAL_BIN:/usr/bin:/bin" "HOME=$HOME" sh -c 'command -v node >/dev/null && command -v npx >/dev/null' \
    && ok "node+npx resolve with minimal PATH (agentation-style spawn)" \
    || die "still unresolvable — check $LOCAL_BIN"
}

main "$@"
