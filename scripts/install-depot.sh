#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${DEVKIT_CACHE:-$HOME/.cache/linux-devkit}"
LOCAL_BIN="$HOME/.local/bin"
INSTALL_DIR="$HOME/.local/lib/linux-devkit/depot"
DEPOT_REPO="depot/cli"

mkdir -p "$CACHE_DIR" "$LOCAL_BIN" "$INSTALL_DIR"

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "Unsupported Depot architecture: $(uname -m)" >&2; exit 1 ;;
esac

version="${DEVKIT_DEPOT_VERSION:-}"
if [[ -z "$version" ]]; then
  version="$(curl -fsSL "https://api.github.com/repos/$DEPOT_REPO/releases/latest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"
fi

archive_name="depot_${version}_linux_${arch}.tar.gz"
archive="$CACHE_DIR/$archive_name"
checksums="$CACHE_DIR/depot_${version}_checksums.txt"
release_base="https://github.com/$DEPOT_REPO/releases/download/v${version}"

if [[ ! -f "$archive" ]]; then
  curl -fsSL --retry 3 -o "$archive.partial" "$release_base/$archive_name"
  mv -f "$archive.partial" "$archive"
fi
if [[ ! -f "$checksums" ]]; then
  curl -fsSL --retry 3 -o "$checksums.partial" "$release_base/depot_${version}_checksums.txt"
  mv -f "$checksums.partial" "$checksums"
fi

expected="$(awk -v name="$archive_name" '$2 == name { print $1 }' "$checksums")"
[[ -n "$expected" ]] || { echo "Depot checksum entry not found for $archive_name" >&2; exit 1; }
actual="$(sha256sum "$archive" | awk '{ print $1 }')"
[[ "$actual" == "$expected" ]] || { echo "Depot checksum mismatch for $archive_name" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -xzf "$archive" -C "$tmp"
install -m 755 "$tmp/bin/depot" "$INSTALL_DIR/depot-real"

cat > "$LOCAL_BIN/depot" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

real="$HOME/.local/lib/linux-devkit/depot/depot-real"
[[ -x "$real" ]] || { echo "Depot binary is missing; rerun linux-devkit/install.sh" >&2; exit 1; }

if [[ -n "${DEPOT_TOKEN:-}" ]]; then
  exec "$real" "$@"
fi

if command -v doppler >/dev/null 2>&1; then
  project="${DEVKIT_DEPOT_DOPPLER_PROJECT:-infrastructure}"
  config="${DEVKIT_DEPOT_DOPPLER_CONFIG:-prd}"
  if doppler secrets get DEPOT_TOKEN --project="$project" --config="$config" --plain >/dev/null 2>&1; then
    exec doppler run --project="$project" --config="$config" -- "$real" "$@"
  fi
fi

echo "Depot authentication unavailable. Set DEPOT_TOKEN or configure DEPOT_TOKEN in Doppler infrastructure/prd." >&2
exit 1
EOF
chmod 755 "$LOCAL_BIN/depot"

# Smoke-test the real binary directly: the wrapper above needs DEPOT_TOKEN
# (via env or Doppler), which may not be configured yet on a fresh VM.
"$INSTALL_DIR/depot-real" version
