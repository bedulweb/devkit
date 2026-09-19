#!/usr/bin/env bash
# serve-opencode.sh — run `opencode serve` with Doppler-backed secrets.
#
# Why this wrapper exists: opencode.jsonc resolves provider/MCP keys from the
# process environment ({env:VAR}). An `opencode serve` started bare (systemd,
# login shell without Doppler env, …) serves the custom models with empty keys
# and every inference fails with HTTP 401. This wrapper preflights the vault,
# injects it via `doppler run`, then execs `opencode serve "$@"`.
#
#   bash ~/linux-devkit/scripts/serve-opencode.sh --port 4096
#   bash ~/linux-devkit/scripts/serve-opencode.sh --check   # preflight only
#
# Vault override: DEVKIT_OPENCODE_DOPPLER_PROJECT / DEVKIT_OPENCODE_DOPPLER_CONFIG
# (falls back to DEVKIT_CODEX_DOPPLER_*), default developer-workstation/dev.
#
# No secret value is ever printed, logged, or written to disk by this script.
set -euo pipefail

PROJECT="${DEVKIT_OPENCODE_DOPPLER_PROJECT:-${DEVKIT_CODEX_DOPPLER_PROJECT:-developer-workstation}}"
CONFIG="${DEVKIT_OPENCODE_DOPPLER_CONFIG:-${DEVKIT_CODEX_DOPPLER_CONFIG:-dev}}"
REQUIRED=(PINKGREEN_API_KEY ROUTEID_API_KEY EXA_API_KEY FIRECRAWL_API_KEY)

have() { command -v "$1" >/dev/null 2>&1; }
die() { printf 'serve-opencode: %s\n' "$*" >&2; exit 1; }

have opencode || die "opencode not found (run: bash ~/linux-devkit/scripts/install-opencode.sh)"
have doppler || die "doppler CLI not found (run: bash ~/linux-devkit/install.sh)"
doppler whoami >/dev/null 2>&1 || die "doppler not authenticated (set DOPPLER_TOKEN or run: doppler login)"

# Preflight: every required key must exist non-empty in env or vault.
# Names only — values are never printed.
missing=()
for k in "${REQUIRED[@]}"; do
  if [[ -n "${!k:-}" ]]; then continue; fi
  val="$(doppler secrets get "$k" --project="$PROJECT" --config="$CONFIG" --plain 2>/dev/null || true)"
  if [[ -z "$val" ]]; then missing+=("$k"); fi
  unset val
done

if [[ "${1:-}" == "--check" ]]; then
  if [[ "${#missing[@]}" -gt 0 ]]; then
    die "missing in $PROJECT/$CONFIG: ${missing[*]}"
  fi
  echo "serve-opencode: preflight ok ($PROJECT/$CONFIG)"
  exit 0
fi

if [[ "${#missing[@]}" -gt 0 ]]; then
  die "missing secrets in $PROJECT/$CONFIG: ${missing[*]} — add them in Doppler, then retry"
fi

exec doppler run --project="$PROJECT" --config="$CONFIG" -- opencode serve "$@"
