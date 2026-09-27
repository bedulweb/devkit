#!/usr/bin/env bash
# restic-backup.sh — scheduled restic backup / forget for a devkit host.
#
#   sudo bash ~/linux-devkit/scripts/restic-backup.sh backup   # every 5 min (timer)
#   sudo bash ~/linux-devkit/scripts/restic-backup.sh forget   # daily (timer)
#
# MUST run as root: it reads /root/projects and writes restores there.
# Credentials NEVER live here: the `drestic` wrapper maps R2_*/RESTIC_*
# from Doppler (infrastructure/prd) at runtime. No IPs, no secrets on disk.
# Single-writer assumption: only the active VPS touches the repo, so
# `unlock` here only ever clears *stale* locks left by a dead rotated VPS.
set -euo pipefail

DRESTIC="${DRESTIC:-$HOME/.local/bin/drestic}"
BACKUP_HOST="${RESTIC_BACKUP_HOST:-devkit}"
BACKUP_ROOT="${RESTIC_BACKUP_ROOT:-/root/projects}"

[[ "$(id -u)" == "0" ]] || { echo "run as root (sudo)" >&2; exit 1; }
[[ -x "$DRESTIC" ]] || { echo "need drestic (bash ~/linux-devkit/scripts/install-restic.sh)" >&2; exit 1; }

# Code history itself is recoverable from git remotes (`devkit restore`);
# the backup protects working state + data. Skip regenerable bulk.
EXCLUDES=(
  --exclude='**/node_modules'
  --exclude='**/.git'
  --exclude='**/.next'
  --exclude='**/dist'
  --exclude='**/build'
  --exclude='**/.cache'
  --exclude='**/coverage'
)

cmd="${1:-backup}"
case "$cmd" in
  backup)
    "$DRESTIC" unlock >/dev/null 2>&1 || true
    exec "$DRESTIC" backup \
      --host "$BACKUP_HOST" \
      --tag devkit-apps,auto \
      "${EXCLUDES[@]}" \
      "$BACKUP_ROOT"
    ;;
  forget)
    exec "$DRESTIC" forget \
      --host "$BACKUP_HOST" \
      --tag devkit-apps,auto \
      --keep-hourly 24 \
      --keep-daily 7 \
      --keep-weekly 4 \
      --prune
    ;;
  *)
    echo "usage: $0 [backup|forget]" >&2
    exit 1
    ;;
esac
