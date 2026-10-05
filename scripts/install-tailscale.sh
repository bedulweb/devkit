#!/usr/bin/env bash
# install-tailscale.sh — install Tailscale + OTOMATIS join (tanpa setup manual)
#
#   bash ~/linux-devkit/scripts/install-tailscale.sh
#
# Alur otomatis:
#   1. Install binary (official install.sh) kalau belum ada
#   2. Ensure tailscaled jalan (systemd enable --now)
#   3. Kalau sudah connected → selesai (idempotent)
#   4. Bootstrap Doppler auth dari $DOPPLER_TOKEN kalau doppler belum login
#   5. Ambil key prioritas: $TAILSCALE_AUTH_KEY → Doppler TAILSCALE_AUTH_KEY
#      @ ${DEVKIT_TAILSCALE_DOPPLER_PROJECT:-infrastructure}/${DEVKIT_TAILSCALE_DOPPLER_CONFIG:-dev}
#   6. tailscale up --auth-key (ephemeral=false, hostname otomatis)
#
# Key dibuat di https://login.tailscale.com/admin/settings/keys (tskey-auth-...)
# Simpan sekali via: devkit set-tailscale-key
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
can_sudo() { have sudo && sudo -n true 2>/dev/null; }
is_root() { [[ "$(id -u)" == "0" ]]; }
run_priv() { if is_root; then "$@"; elif can_sudo; then sudo "$@"; else "$@"; fi; }

TSPROJECT="${DEVKIT_TAILSCALE_DOPPLER_PROJECT:-${INFRA_DOPPLER_PROJECT:-infrastructure}}"
TSCONFIG="${DEVKIT_TAILSCALE_DOPPLER_CONFIG:-${INFRA_DOPPLER_CONFIG:-dev}}"

# ── 0. bootstrap Doppler auth (fresh VPS: DOPPLER_TOKEN ada di env tapi CLI belum login) ──
if have doppler && ! doppler whoami >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]]; then
  printf '%s\n' "$DOPPLER_TOKEN" | doppler configure set token >/dev/null 2>&1 || true
fi

resolve_key() {
  if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then printf '%s' "$TAILSCALE_AUTH_KEY"; return 0; fi
  if have doppler; then
    doppler secrets get TAILSCALE_AUTH_KEY --project="$TSPROJECT" --config="$TSCONFIG" --plain 2>/dev/null || true
  fi
}

# ── 1. install binary ──
if ! have tailscale; then
  echo "==> install Tailscale (official install.sh)"
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "  ✓ tailscale $(tailscale --version 2>/dev/null | head -1)"
fi

# ── 2. ensure daemon ──
if have systemctl; then
  if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
    run_priv systemctl enable --now tailscaled >/dev/null 2>&1 || true
  fi
fi
if ! pgrep -x tailscaled >/dev/null 2>&1; then
  if have tailscaled && (is_root || can_sudo); then
    echo "==> starting tailscaled"
    run_priv tailscaled >/var/log/tailscaled.log 2>&1 &
    sleep 2
  fi
fi

# ── 3. sudah connected? selesai ──
if tailscale status >/dev/null 2>&1; then
  echo "  ✓ Tailscale already connected:"
  tailscale status 2>/dev/null | head -3 || true
  exit 0
fi

# ── 4. auto-join ──
KEY="$(resolve_key || true)"
if [[ -z "$KEY" ]]; then
  echo "  ! Tailscale terinstall tapi belum join (tidak ada key)."
  echo "    Setup sekali: devkit set-tailscale-key  →  devkit tailscale-up"
  echo "    (Doppler: TAILSCALE_AUTH_KEY @ ${TSPROJECT}/${TSCONFIG}, atau export TAILSCALE_AUTH_KEY=tskey-auth-...)"
  exit 0
fi
case "$KEY" in
  tskey-auth-*) ;;
  tskey-api-*) echo "  ✗ Key ini tskey-api-... (API key, tidak bisa buat join). Buat tskey-auth-... di https://login.tailscale.com/admin/settings/keys" >&2; exit 0 ;;
  *) echo "  ✗ Format key tidak dikenal (harus tskey-auth-...)" >&2; exit 0 ;;
esac

HOSTNAME="${TAILSCALE_HOSTNAME:-$(hostname)}"
echo "==> tailscale up --hostname=$HOSTNAME (auto, key dari ${TAILSCALE_AUTH_KEY:+env}${TAILSCALE_AUTH_KEY:-Doppler $TSPROJECT/$TSCONFIG})"
# shellcheck disable=SC2086
run_priv tailscale up --auth-key="$KEY" --hostname="$HOSTNAME" ${TAILSCALE_EXTRA_ARGS:-} || {
  echo "  ✗ tailscale up gagal — cek key expired/reusable di admin console" >&2
  exit 0
}
unset KEY
echo "  ✓ joined:"
tailscale status 2>/dev/null | head -3 || true
