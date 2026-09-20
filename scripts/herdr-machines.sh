#!/usr/bin/env bash
# herdr-machines.sh — pasang SSH key + ssh config + herdr saved machines.
# Idempoten: aman dijalankan ulang (yang sudah ada di-skip).
#
#   bash ~/linux-devkit/scripts/herdr-machines.sh
#
# Daftar mesin: ../config/herdr-machines (alias user host port label...)
# Env:
#   DEVKIT_SSH_DOPPLER_PROJECT  project Doppler berisi SSH_PRIVATE_KEY (default: infrastructure)
#   DEVKIT_SSH_DOPPLER_CONFIG   config Doppler (default: dev)
#   DEVKIT_SSH_KEY              path private key (default: ~/.ssh/id_devkit)
#
# Butuh: herdr terinstall, dan (kalau key belum ada) Doppler terautentikasi.
# Remote yang herdr-nya jadul/tidak kompatibel TIDAK dipaksa: di-skip + warning,
# selesaikan manual sekali secara interaktif: herdr machine add <target> --label <label>
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
log()  { printf '==> %s\n' "$*"; }
ok()   { printf '  ok: %s\n' "$*"; }
warn() { printf '  warn: %s\n' "$*" >&2; }

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACHINES_FILE="${DEVKIT_HERDR_MACHINES_FILE:-$KIT_DIR/config/herdr-machines}"
KEY="${DEVKIT_SSH_KEY:-$HOME/.ssh/id_devkit}"
SSH_PROJECT="${DEVKIT_SSH_DOPPLER_PROJECT:-infrastructure}"
SSH_CONFIG_NAME="${DEVKIT_SSH_DOPPLER_CONFIG:-dev}"

have herdr || { warn "herdr belum terinstall — skip (jalankan install.sh --with-herdr dulu)"; exit 0; }
[[ -f "$MACHINES_FILE" ]] || { warn "config $MACHINES_FILE tidak ada — skip"; exit 0; }

# ── 1. SSH key ──────────────────────────────────────────────────────────────
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ -s "$KEY" ]]; then
  ok "key sudah ada: $KEY"
elif have doppler && doppler secrets get SSH_PRIVATE_KEY \
      --project "$SSH_PROJECT" --config "$SSH_CONFIG_NAME" --plain >"$KEY.tmp" 2>/dev/null \
      && [[ -s "$KEY.tmp" ]]; then
  mv -f "$KEY.tmp" "$KEY"
  chmod 600 "$KEY"
  ok "key diambil dari Doppler ($SSH_PROJECT/$SSH_CONFIG_NAME) → $KEY"
else
  rm -f "$KEY.tmp"
  warn "tidak bisa ambil SSH_PRIVATE_KEY dari Doppler ($SSH_PROJECT/$SSH_CONFIG_NAME)"
  warn "  isi manual $KEY atau Doppler login dulu, lalu ulangi script ini"
  exit 0
fi
chmod 600 "$KEY"
ssh-keygen -y -f "$KEY" >"$KEY.pub" 2>/dev/null || { warn "key $KEY rusak — perbaiki manual"; exit 0; }
PUB="$(cat "$KEY.pub")"

# IP lokal (untuk deteksi entri yang menunjuk ke mesin ini sendiri)
LOCAL_IPS="$( (hostname -I 2>/dev/null; tailscale ip 2>/dev/null) | tr ' ' '\n' | grep -E '^[0-9a-fA-F:.]+$' || true)"

# ── 2. ssh config (blok managed, ditulis ulang tiap run) ────────────────────
BEGIN="# devkit-herdr BEGIN (jangan edit manual — diatur scripts/herdr-machines.sh)"
END="# devkit-herdr END"
TMP_CFG="$(mktemp)"
BLOCK="$(mktemp)"
{
  echo "$BEGIN"
  # shellcheck disable=SC2162
  while read alias user host port label; do
    [[ -z "${alias:-}" || "$alias" == \#* ]] && continue
    [[ -z "${user:-}" || -z "${host:-}" ]] && continue
    port="${port:-22}"
    # entri self (putravm di mesinnya sendiri): otorisasi pub key sendiri
    if echo "$LOCAL_IPS" | grep -qxF "$host" && [[ "$user" == "$(whoami)" ]]; then
      touch "$HOME/.ssh/authorized_keys"
      chmod 600 "$HOME/.ssh/authorized_keys"
      grep -qxF "$PUB" "$HOME/.ssh/authorized_keys" 2>/dev/null \
        || echo "$PUB" >>"$HOME/.ssh/authorized_keys"
    fi
    printf 'Host %s\n  HostName %s\n  User %s\n  Port %s\n  IdentityFile %s\n' \
      "$alias" "$host" "$user" "$port" "$KEY"
  done <"$MACHINES_FILE"
  echo "$END"
} >"$BLOCK"
touch "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"
# buang blok lama, tambah blok baru
awk -v b="$BEGIN" -v e="$END" '
  $0==b {skip=1; next} $0==e {skip=0; next} !skip {print}
' "$HOME/.ssh/config" >"$TMP_CFG"
cat "$BLOCK" >>"$TMP_CFG"
mv -f "$TMP_CFG" "$HOME/.ssh/config"
rm -f "$BLOCK"
ok "ssh config ditulis ($(grep -c '^Host ' "$HOME/.ssh/config") alias)"

# ── 3. herdr saved machines ─────────────────────────────────────────────────
LIST_JSON="$(herdr machine list --json 2>/dev/null || echo '[]')"
# shellcheck disable=SC2162
while read alias user host port label; do
  [[ -z "${alias:-}" || "$alias" == \#* ]] && continue
  [[ -z "${user:-}" || -z "${host:-}" ]] && continue
  label="${label:-$alias}"
  if echo "$LIST_JSON" | grep -q "\"label\": *\"$label\""; then
    ok "$label: sudah terdaftar — skip"
    continue
  fi
  if ! timeout 15 ssh -n -o BatchMode=yes -o ConnectTimeout=8 \
      -o StrictHostKeyChecking=accept-new "$alias" true 2>/dev/null; then
    warn "$label ($alias): SSH gagal — skip (cek key/jaringan, lalu ulangi)"
    continue
  fi
  log "add $label ($alias)..."
  if timeout 120 herdr machine add "$alias" --label "$label" </dev/null 2>&1 | tail -n 3; then
    ok "$label terdaftar"
  else
    warn "$label: machine add butuh approval interaktif (remote jadul/tak kompatibel)"
    warn "  selesaikan manual: herdr machine add $alias --label \"$label\""
  fi
  LIST_JSON="$(herdr machine list --json 2>/dev/null || echo '[]')"
done <"$MACHINES_FILE"

ok "selesai"; herdr machine list 2>/dev/null || true
