#!/usr/bin/env bash
# =============================================================================
# export-env.sh — load secrets into current shell
#
# Usage (WAJIB pakai source, bukan bash):
#   source ~/linux-devkit/scripts/export-env.sh
#   # atau
#   . ~/linux-devkit/scripts/export-env.sh
#
# Env file dicari berurutan:
#   1) $DEVKIT_ENV_FILE
#   2) ~/.devkit.env
#   3) ~/linux-devkit/.devkit.env
# =============================================================================

_DEVKIT_EXPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
_ENV_FILE=""

for f in \
  "${DEVKIT_ENV_FILE:-}" \
  "${HOME}/.devkit.env" \
  "${_DEVKIT_EXPORT_DIR}/.devkit.env" \
  "${HOME}/linux-devkit/.devkit.env"
do
  if [[ -n "${f}" && -f "${f}" ]]; then
    _ENV_FILE="${f}"
    break
  fi
done

if [[ -z "${_ENV_FILE}" ]]; then
  echo "✗ Tidak ketemu file env."
  echo "  Buat dulu:"
  echo "    cp ~/linux-devkit/.devkit.env.example ~/.devkit.env"
  echo "    nano ~/.devkit.env"
  return 1 2>/dev/null || exit 1
fi

# shellcheck disable=SC1090
set -a
source "${_ENV_FILE}"
set +a

# Normalisasi alias
if [[ -n "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
  export GITHUB_TOKEN="${GH_TOKEN}"
fi
if [[ -n "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
  export GH_TOKEN="${GITHUB_TOKEN}"
fi

export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${HOME}/.opencode/bin:${HOME}/.local/go/bin:${HOME}/go/bin:${PATH:-}"
export GOPATH="${GOPATH:-$HOME/go}"
export DOPPLER_API_HOST="${DOPPLER_API_HOST:-https://api.doppler.com}"
export DOPPLER_DASHBOARD_HOST="${DOPPLER_DASHBOARD_HOST:-https://dashboard.doppler.com}"
export DOPPLER_CONFIG="${DOPPLER_CONFIG:-dev}"

_status() {
  # print SET/NOT SET without leaking values
  local v="${1:-}"
  if [[ -n "$v" ]]; then
    printf 'SET (%s chars)' "${#v}"
  else
    printf 'NOT SET'
  fi
}

echo "✓ loaded: ${_ENV_FILE}"
echo "  GH_TOKEN:          $(_status "${GH_TOKEN:-}")"
echo "  DOPPLER_TOKEN:     $(_status "${DOPPLER_TOKEN:-}")"
echo "  DOPPLER_PROJECT:   ${DOPPLER_PROJECT:-<belum di-set>}"
echo "  DOPPLER_CONFIG:    ${DOPPLER_CONFIG:-dev}"
echo ""
echo "Next:"
echo "  bash ~/linux-devkit/scripts/install-full.sh"
echo "  # atau step-by-step: bash ~/linux-devkit/run.sh"
