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
require 'RESTIC_BACKUP_ROOT' "$backup_script" 'backup root is overridable via env'
require '$HOME/projects' "$backup_script" 'backup defaults to $HOME/projects (any user)'
require 'node_modules' "$backup_script" 'backup excludes regenerable bulk (node_modules)'
require '--host' "$backup_script" 'backup pins a stable --host (survives VPS rotation)'
require 'forget' "$backup_script" 'backup script supports forget/prune mode'
require 'drestic' "$backup_script" 'backup goes through the drestic Doppler wrapper (no secrets on disk)'

# user-agnostic systemd units: %h resolves per-user, name stamped at install
require 'User=__DEVKIT_USER__' "$root/systemd/restic-backup.service" 'service user is a placeholder, not a hardcoded name'
require 'User=__DEVKIT_USER__' "$root/systemd/restic-forget.service" 'forget service user is a placeholder'
require 'ExecStart=%h/linux-devkit' "$root/systemd/restic-backup.service" 'service resolves paths via %h (any user)'
require 'SUDO_USER' "$timer_script" 'timer installer targets the invoking user by default'
require '__DEVKIT_USER__' "$timer_script" 'timer installer stamps the real username into units'

# systemd units
require 'OnCalendar=' "$root/systemd/restic-backup.timer" 'backup timer exists'
require '*:0/5' "$root/systemd/restic-backup.timer" 'backup runs every 5 minutes'
require 'restic-backup.sh backup' "$root/systemd/restic-backup.service" 'backup service calls the job script'
require 'OnCalendar=daily' "$root/systemd/restic-forget.timer" 'forget runs daily'
require 'systemctl enable --now' "$timer_script" 'timer installer enables both timers'

# no hardcoded /root or IPv4 literals anywhere in the restic path
if grep -rn '/root' "$backup_script" "$timer_script" "$root/systemd/" >/dev/null; then
  printf 'FAIL: hardcoded /root in restic path (breaks non-root users)\n' >&2
  grep -rn '/root' "$backup_script" "$timer_script" "$root/systemd/" >&2 || true
  exit 1
fi
if grep -rEn '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
  "$backup_script" "$timer_script" "$root/systemd/" | grep -v '1\.0\.0\|0\.19\.1' >/dev/null; then
  printf 'FAIL: hardcoded IP literal in restic path\n' >&2
  exit 1
fi

# shellcheck-lite: every script file must parse
bash -n "$backup_script" && bash -n "$timer_script"

printf 'PASS: restic auto-backup every 5 minutes, any user, IP-agnostic\n'
