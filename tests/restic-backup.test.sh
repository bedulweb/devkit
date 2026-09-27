#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_script="$root/scripts/restic-backup.sh"
timer_script="$root/scripts/install-restic-timer.sh"

require() {
  local pattern="$1" file="$2" description="$3"
  if ! grep -qF -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    exit 1
  fi
}

# job script
require 'BACKUP_ROOT' "$backup_script" 'backup script defines BACKUP_ROOT'
require '/root/projects' "$backup_script" 'backup covers /root/projects (wazapin + zero + future apps)'
require 'node_modules' "$backup_script" 'backup excludes regenerable bulk (node_modules)'
require '--host' "$backup_script" 'backup pins a stable --host (survives VPS rotation)'
require 'forget' "$backup_script" 'backup script supports forget/prune mode'
require 'drestic' "$backup_script" 'backup goes through the drestic Doppler wrapper (no secrets on disk)'

# systemd units
require 'OnCalendar=' "$root/systemd/restic-backup.timer" 'backup timer exists'
require '*:0/5' "$root/systemd/restic-backup.timer" 'backup runs every 5 minutes'
require 'restic-backup.sh backup' "$root/systemd/restic-backup.service" 'backup service calls the job script'
require 'OnCalendar=daily' "$root/systemd/restic-forget.timer" 'forget runs daily'
require 'systemctl enable --now' "$timer_script" 'timer installer enables both timers'

# no hardcoded IPv4 literals anywhere in the restic path
if grep -rEn '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
  "$backup_script" "$timer_script" "$root/systemd/" | grep -v '1\.0\.0\|0\.19\.1' >/dev/null; then
  printf 'FAIL: hardcoded IP literal in restic backup path\n' >&2
  exit 1
fi

printf 'PASS: restic auto-backup every 5 minutes (wazapin + zero), IP-agnostic\n'
