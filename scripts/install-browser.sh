#!/usr/bin/env bash
# install-browser.sh — Install agent-browser CLI + Chromium + auto-close.
#
# Kenapa bukan opencode built-in browser (browser.tabs.open)?
#   Built-in itu butuh desktop app + experimental browser setting (CDP bridge
#   ke browser desktop). Di VPS/headless tidak ada yang connect →
#   "[browser.disconnected]". agent-browser CLI jalan headless via CDP
#   langsung, jadi cocok untuk VPS.
#
# Auto-close (biar tab/sesi ga numpuk):
#   1) Daemon agent-browser otomatis mati setelah idle
#      (AGENT_BROWSER_IDLE_TIMEOUT_MS, default kita 10 menit vs bawaan 1 jam).
#      Tanpa --restore, shutdown membuang tab transient.
#   2) Cron reaper tiap 15 menit: kalau ada sesi nganggur >15 menit dan tidak
#      ada proses agent-browser aktif, jalankan `close --all`.
#   3) Wajib pola pakai: session bernama per tugas + `close` di akhir.
#
# Usage:
#   bash ~/linux-devkit/scripts/install-browser.sh
#   bash ~/linux-devkit/scripts/install-browser.sh --with-deps   # apt libs chromium (butuh sudo)
#   AGENT_BROWSER_IDLE_TIMEOUT_MS=600000 bash ~/linux-devkit/scripts/install-browser.sh
set -euo pipefail

IDLE_MS="${AGENT_BROWSER_IDLE_TIMEOUT_MS:-600000}"  # 10 menit
WITH_DEPS=0
[[ "${1:-}" == "--with-deps" ]] && WITH_DEPS=1

log() { printf '\033[1;36m==> browser:\033[0m %s\n' "$*"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }

export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
if ! command -v npm >/dev/null 2>&1; then
  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
fi
command -v npm >/dev/null 2>&1 || { warn "npm tidak ketemu — install nodejs dulu"; exit 1; }

log "install agent-browser CLI"
npm i -g agent-browser
ok "$(agent-browser --version 2>/dev/null || echo installed)"

log "install Chromium"
if [[ "$WITH_DEPS" == "1" ]]; then
  agent-browser install --with-deps || agent-browser install
else
  agent-browser install || agent-browser install --with-deps
fi
ok "chromium ready"

# ── idle timeout default (idempotent) ──
ENV_FILE="$HOME/.linux-devkit/env"
MARK="# devkit: agent-browser idle timeout"
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
if grep -q "AGENT_BROWSER_IDLE_TIMEOUT_MS" "$ENV_FILE"; then
  ok "idle timeout sudah ada di $ENV_FILE"
else
  {
    echo "$MARK"
    echo "export AGENT_BROWSER_IDLE_TIMEOUT_MS=\"$IDLE_MS\""
  } >>"$ENV_FILE"
  ok "idle timeout ${IDLE_MS}ms → $ENV_FILE"
fi
export AGENT_BROWSER_IDLE_TIMEOUT_MS="$IDLE_MS"

# ── cron reaper (idempotent) ──
REAP="$HOME/linux-devkit/scripts/browser-reap.sh"
CRON_LINE="*/15 * * * * AGENT_BROWSER_IDLE_TIMEOUT_MS=\"$IDLE_MS\" bash \"$REAP\" >>\"$HOME/.linux-devkit/browser-reap.log\" 2>&1"
if command -v crontab >/dev/null 2>&1; then
  if crontab -l 2>/dev/null | grep -qF "$REAP"; then
    ok "cron reaper sudah terpasang"
  else
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    ok "cron reaper tiap 15 menit terpasang"
  fi
else
  warn "crontab tidak ada — reaper tidak dipasang, andalkan idle-timeout daemon"
fi

cat <<'EOF'

Pola pakai (wajib session bernama + close di akhir):
  export AGENT_BROWSER_SESSION="$(agent-browser session id --scope worktree --prefix task)"
  agent-browser open http://app.wzpn.us
  agent-browser snapshot -i
  # ... klik/isi ...
  agent-browser close --all   # tutup semua sesi tugas ini; reaper cron jadi safety net

Aturan:
- Jangan pakai sesi default (shared semua agent).
- Selalu `close` di akhir tugas; daemon juga auto-mati setelah idle.
- Cek sesi: agent-browser session list
EOF
