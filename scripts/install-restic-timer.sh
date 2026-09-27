#!/usr/bin/env bash
# install-restic-timer.sh — enable the 5-minute restic backup + daily forget.
# Run ONCE per VPS (as root, needs systemd):
#   sudo bash ~/linux-devkit/scripts/install-restic-timer.sh
# Idempotent: safe to re-run.
set -euo pipefail
[[ "$(id -u)" == "0" ]] || { echo "run as root (sudo)" >&2; exit 1; }

KIT="${KIT:-$HOME/linux-devkit}"
[[ -d "$KIT/systemd" ]] || KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for unit in restic-backup.service restic-backup.timer restic-forget.service restic-forget.timer; do
  install -m 644 "$KIT/systemd/$unit" "/etc/systemd/system/$unit"
done
systemctl daemon-reload
systemctl enable --now restic-backup.timer restic-forget.timer
echo "active timers:"
systemctl list-timers restic-backup.timer restic-forget.timer --all --no-pager | tail -n 5
