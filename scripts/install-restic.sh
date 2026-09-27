#!/usr/bin/env bash
# install-restic.sh — restic backup tool + Doppler credential wrapper.
#
# Design (same as the rest of this kit):
#   - user-space: binary → ~/.local/bin (no root required)
#   - idempotent: skips when the pinned version is already present
#   - IP-agnostic: NO hardcoded hosts/IPs anywhere. Endpoint, repo URL and
#     keys all resolve from Doppler (infrastructure/prd) at *runtime*,
#     so this works on any VPS rotation without edits.
#   - restore stays manual (snapshots are point-in-time by nature):
#       drestic snapshots
#       drestic restore latest --target /tmp/restore --host devkit
#
# Standalone (existing VM):
#   bash ~/linux-devkit/scripts/install-restic.sh
# Or via the main installer (fresh VM): restic is in the always-block.
set -euo pipefail

RESTIC_VERSION="${RESTIC_VERSION:-0.19.1}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
CACHE_DIR="${DEVKIT_CACHE:-$HOME/.cache/linux-devkit}"

log()  { printf '==> %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

arch_go() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "Unsupported arch: $(uname -m)" ;;
  esac
}

latest_tag() {
  curl -fsSL "https://api.github.com/repos/restic/restic/releases/latest" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2>/dev/null \
    || true
}

decompress_bz2() {
  # $1 = src.bz2, $2 = dest
  local src="$1" dest="$2"
  if have bzip2; then
    bzip2 -dck "$src" > "$dest"
    return 0
  fi
  if python3 -c 'import bz2' 2>/dev/null; then
    python3 - "$src" "$dest" <<'PY'
import bz2, sys
with bz2.open(sys.argv[1], 'rb') as f, open(sys.argv[2], 'wb') as o:
    o.write(f.read())
PY
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bzip2 >/dev/null 2>&1 || true
    if have bzip2; then
      bzip2 -dck "$src" > "$dest"
      return 0
    fi
  fi
  return 1
}

install_restic_binary() {
  if [[ -x "$LOCAL_BIN/restic" ]] && "$LOCAL_BIN/restic" version 2>/dev/null | grep -q "$RESTIC_VERSION"; then
    ok "restic $($LOCAL_BIN/restic version 2>/dev/null | head -1)"
    return 0
  fi
  local ver="$RESTIC_VERSION" arch tgz bin
  arch="$(arch_go)"
  # prefer latest release, fall back to pinned version when offline/rate-limited
  if [[ "${RESTIC_PINNED:-0}" != "1" ]]; then
    ver="$(latest_tag)"
    [[ -n "$ver" ]] || ver="$RESTIC_VERSION"
  fi
  log "install restic $ver"
  mkdir -p "$LOCAL_BIN" "$CACHE_DIR"
  tgz="$CACHE_DIR/restic_${ver}_linux_${arch}.bz2"
  if [[ ! -f "$tgz" ]]; then
    curl -fsSL --retry 3 --retry-delay 1 \
      -o "$tgz.partial" "https://github.com/restic/restic/releases/download/v${ver}/restic_${ver}_linux_${arch}.bz2"
    mv "$tgz.partial" "$tgz"
  else
    ok "cached $(basename "$tgz")"
  fi
  bin="$CACHE_DIR/restic_${ver}_linux_${arch}"
  decompress_bz2 "$tgz" "$bin" || die "need bzip2 (or python3-bz2) to unpack restic"
  chmod +x "$bin"
  install -m 755 "$bin" "$LOCAL_BIN/restic"
  ok "restic $($LOCAL_BIN/restic version | head -1)"
}

install_drestic_wrapper() {
  # drestic = restic with credentials mapped from Doppler at runtime.
  # R2_* key names (Doppler) → AWS_* env names (what restic expects).
  cat > "$LOCAL_BIN/drestic" <<'EOF'
#!/usr/bin/env bash
# drestic — restic backed by Doppler credentials (no secrets on disk, no IPs).
#   drestic snapshots
#   drestic restore latest --target /tmp/restore --host devkit
# Env overrides: RESTIC_DOPPLER_PROJECT (default: infrastructure),
#                RESTIC_DOPPLER_CONFIG  (default: prd).
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
command -v doppler >/dev/null 2>&1 || { echo "need doppler (DOPPLER_TOKEN). See ~/.devkit.env" >&2; exit 1; }
command -v restic >/dev/null 2>&1 || { echo "need restic. Run: bash ~/linux-devkit/scripts/install-restic.sh" >&2; exit 1; }
exec doppler run --project "${RESTIC_DOPPLER_PROJECT:-infrastructure}" --config "${RESTIC_DOPPLER_CONFIG:-prd}" -- \
  sh -c 'export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" RESTIC_REPOSITORY="$RESTIC_REPOSITORY" RESTIC_PASSWORD="$RESTIC_PASSWORD"; exec restic "$@"' sh "$@"
EOF
  chmod 755 "$LOCAL_BIN/drestic"
  ok "drestic → $LOCAL_BIN/drestic"
}

main() {
  install_restic_binary
  install_drestic_wrapper
  echo
  echo "Manual restore (snapshots are point-in-time):"
  echo "  drestic snapshots"
  echo "  drestic restore latest --target /tmp/restore --host devkit"
}

main "$@"
