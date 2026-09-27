#!/usr/bin/env bash
# install-restic-timer.sh — enable the 5-minute restic backup + daily forget.
# Run ONCE per VPS (needs sudo for /etc/systemd/system + systemctl):
#   sudo bash ~/linux-devkit/scripts/install-restic-timer.sh
# Works for ANY user: the timer runs as the invoking user (or $TARGET_USER),
# paths resolve via systemd %h (that user's home). Nothing user-specific baked in.
# Idempotent: safe to re-run.
set -euo pipefail
[[ "$(id -u)" == "0" ]] || { echo "run with sudo (writes /etc/systemd/system)" >&2; exit 1; }

TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
id "$TARGET_USER" >/dev/null 2>&1 || { echo "unknown user: $TARGET_USER" >&2; exit 1; }

KIT="${KIT:-$HOME/linux-devkit}"
[[ -d "$KIT/systemd" ]] || KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -d "$KIT/systemd" ]] || { echo "kit not found (set KIT=)" >&2; exit 1; }

for unit in restic-backup.service restic-backup.timer restic-forget.service restic-forget.timer; do
  sed "s/__DEVKIT_USER__/$TARGET_USER/" "$KIT/systemd/$unit" > "/etc/systemd/system/$unit"
  chmod 644 "/etc/systemd/system/$unit"
done
systemctl daemon-reload
systemctl enable --now restic-backup.timer restic-forget.timer
echo "timer user → $TARGET_USER"
echo "active timers:"
systemctl list-timers restic-backup.timer restic-forget.timer --all --no-pager | tail -n 5
