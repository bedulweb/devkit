#!/usr/bin/env bash
# Hanya export + siapkan Doppler CLI (token / service account)
#
#   source ~/linux-devkit/scripts/export-doppler.sh
#   doppler run --project=wazapin-platform --config=dev -- printenv | head
#
# shellcheck disable=SC1091
_KIT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"
if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
  for f in "${HOME}/.devkit.env" "${_KIT}/.devkit.env"; do
    [[ -f "$f" ]] || continue
    # shellcheck disable=SC1090
    set -a; source "$f"; set +a
    break
  done
fi

export DOPPLER_PROJECT="${DOPPLER_PROJECT:-}"
export DOPPLER_CONFIG="${DOPPLER_CONFIG:-dev}"
export DOPPLER_API_HOST="${DOPPLER_API_HOST:-https://api.doppler.com}"
export DOPPLER_DASHBOARD_HOST="${DOPPLER_DASHBOARD_HOST:-https://dashboard.doppler.com}"

if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
  echo "✗ Isi dulu di ~/.devkit.env:"
  echo "    DOPPLER_TOKEN=dp.st.xxx"
  echo "    DOPPLER_PROJECT=wazapin-platform   # project default"
  echo "    DOPPLER_CONFIG=dev                 # config default"
  return 1 2>/dev/null || exit 1
fi

export DOPPLER_TOKEN

echo "✓ Doppler credentials loaded"
echo "  PROJECT: ${DOPPLER_PROJECT:-<belum di-set>}"
echo "  CONFIG:  ${DOPPLER_CONFIG}"
echo "  TOKEN:   dp.st.…${DOPPLER_TOKEN: -6}"

if command -v doppler >/dev/null 2>&1; then
  if doppler whoami >/dev/null 2>&1; then
    echo "✓ Doppler CLI authenticated"
    doppler whoami 2>/dev/null | head -12 || true
  else
    echo "⚠ doppler whoami gagal — coba: doppler configure set token \"\$DOPPLER_TOKEN\""
  fi
else
  echo "⚠ doppler CLI belum terpasang. Jalankan: bash ~/linux-devkit/install.sh"
fi
