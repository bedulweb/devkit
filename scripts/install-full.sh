#!/usr/bin/env bash
# =============================================================================
# install-full.sh — export env + full install sampai siap pakai
#
# 1) Isi token:
#      cp ~/linux-devkit/.devkit.env.example ~/.devkit.env
#      nano ~/.devkit.env
#
# 2) Jalankan:
#      bash ~/linux-devkit/scripts/install-full.sh
#
# Atau sekali di VM baru (setelah env file ada):
#      curl -fsSL https://raw.githubusercontent.com/bedulweb/devkit/main/scripts/install-full.sh | bash
# =============================================================================
set -euo pipefail

KIT_REPO="${DEVKIT_KIT_REPO:-https://github.com/bedulweb/devkit.git}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

# ── pastikan kit ada ────────────────────────────────────────────────────────
if [[ ! -f "${HOME}/linux-devkit/run.sh" ]]; then
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "${KIT_REPO}" "${HOME}/linux-devkit"
  else
    echo "Need git. Install: sudo apt-get install -y git curl"
    exit 1
  fi
else
  git -C "${HOME}/linux-devkit" pull --ff-only 2>/dev/null || true
fi

KIT="${HOME}/linux-devkit"

# ── load env ────────────────────────────────────────────────────────────────
if [[ -f "${HOME}/.devkit.env" ]] || [[ -f "${KIT}/.devkit.env" ]] || [[ -n "${DEVKIT_ENV_FILE:-}" ]]; then
  # shellcheck disable=SC1091
  source "${KIT}/scripts/export-env.sh"
else
  echo "⚠  Belum ada ~/.devkit.env"
  echo "   Buat dulu:"
  echo "     cp ${KIT}/.devkit.env.example ~/.devkit.env"
  echo "     nano ~/.devkit.env"
  echo ""
  echo "   Lanjut tanpa secret? (private clone & Doppler akan skip)"
  echo "   Tekan Enter untuk lanjut, Ctrl+C untuk batal."
  read -r _
fi

# ── full pipeline ───────────────────────────────────────────────────────────
echo ""
echo "==> running full setup (run.sh)..."
bash "${KIT}/run.sh"

# ── Doppler configure explicit (kalau token ada) ────────────────────────────
if command -v doppler >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]]; then
  echo ""
  echo "==> Doppler configure..."
  export DOPPLER_TOKEN
  if doppler whoami >/dev/null 2>&1; then
    echo "✓ Doppler OK"
  else
    doppler configure set token "${DOPPLER_TOKEN}" 2>/dev/null \
      && echo "✓ Doppler OK" \
      || echo "⚠ Doppler configure gagal — cek DOPPLER_TOKEN di ~/.devkit.env"
  fi
fi

# ── ringkas ─────────────────────────────────────────────────────────────────
export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${PATH}"
echo ""
echo "════════════════════════════════════════"
echo "  SELESAI"
echo "════════════════════════════════════════"
if command -v devkit >/dev/null 2>&1; then
  devkit list || true
  echo ""
  echo "Masuk project:"
  echo "  cd \"\$(devkit path wabase-core)\""
  echo "  cd \"\$(devkit path wazapin-platform)\""
  echo "  cd \"\$(devkit path wazapin-web)\""
  echo "  cd \"\$(devkit path betterpay)\""
  echo ""
  echo "Dengan secrets:"
  echo "  doppler run --project=wazapin-platform --config=${DOPPLER_CONFIG:-dev} -- bun run dev"
fi
