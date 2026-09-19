#!/usr/bin/env bash
# browser-reap.sh — Safety net: tutup sesi agent-browser yang nganggur.
# Dijalankan cron tiap 15 menit oleh install-browser.sh.
# Tidak membunuh sesi aktif: skip kalau ada proses agent-browser client jalan,
# atau socket daemon masih fresh (<15 menit).
set -u

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
if ! command -v agent-browser >/dev/null 2>&1; then
  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
fi
command -v agent-browser >/dev/null 2>&1 || exit 0

LIST="$(agent-browser session list --json 2>/dev/null || echo '')"
echo "$LIST" | grep -q '"sessions":\[\]' && exit 0  # tidak ada sesi → selesai
[[ -z "$LIST" ]] && exit 0

# Ada proses client aktif? (kecualikan diri sendiri/reap) → jangan ganggu.
if pgrep -f "agent-browser (open|snapshot|click|fill|type|press|screenshot|read|eval|wait|tabs)" >/dev/null 2>&1; then
  exit 0
fi

# Socket daemon masih fresh? → jangan ganggu.
SOCKDIR="/run/user/${UID:-0}/agent-browser"
if [[ -d "$SOCKDIR" ]] && [[ -z "$(find "$SOCKDIR" -mmin +15 2>/dev/null)" ]]; then
  exit 0
fi

agent-browser close --all >/dev/null 2>&1 || true
echo "$(date -u +%FT%TZ) reaped idle sessions"
