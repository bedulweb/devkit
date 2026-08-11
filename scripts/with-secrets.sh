#!/usr/bin/env bash
# Usage: with-secrets grok | with-secrets opencode | with-secrets -- env
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.local/go/bin:$PATH"
if command -v doppler >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]]; then
  if [[ -n "${DOPPLER_PROJECT:-}" ]]; then
    exec doppler run --project="$DOPPLER_PROJECT" --config="${DOPPLER_CONFIG:-dev}" -- "$@"
  else
    exec doppler run --config="${DOPPLER_CONFIG:-dev}" -- "$@"
  fi
fi
# fallback: plain exec if already exported
exec "$@"
