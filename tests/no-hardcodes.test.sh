#!/usr/bin/env bash
# no-hardcodes regression guard: the installer must stay dynamic
# (any user, any VPS, any IP). Intentional exceptions live OUTSIDE the
# scanned paths: config/herdr-machines (machine registry IS an IP list)
# and docs/AGENTS prose. Scan only executable/config-as-code.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

code_files() {
  find "$root" -path "$root/.git" -prune -o -path "$root/tests/no-hardcodes*" -prune -o \
    \( -name '*.sh' -o -name '*.service' -o -name '*.timer' \
       -o -name 'cloud-init.yaml' -o -name 'run.sh' -o -name 'install.sh' \
       -o -name 'bootstrap-vps.sh' \) -print
}

# 1. no IPv4 literals in code (versions like 1.0.0 have only 3 parts — safe)
if code_files | xargs grep -HEn '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' 2>/dev/null; then
  printf 'FAIL: hardcoded IPv4 in installer code\n' >&2
  fail=1
fi

# 2. no hardcoded home dirs (except Linuxbrew's official system prefix,
#    which is identical on every machine and not a username)
if code_files | xargs grep -HEn '/root/|/root"|/home/[a-z_]+' 2>/dev/null \
  | grep -v '/home/linuxbrew' | grep -vE '\$HOME|\$USER|%h|__DEVKIT|SUDO_USER|TARGET_USER'; then
  printf 'FAIL: hardcoded home dir in installer code (use $HOME/%%h)\n' >&2
  fail=1
fi

# 3. no real secrets (placeholders like dp.st.xxx / *_ISI_DISINI in
#    *.example files are fill-in hints, not secrets)
if grep -rEn 'dp\.(st|ct)\.[A-Za-z0-9]{8,}|ghp_[A-Za-z0-9]{8,}|github_pat_[A-Za-z0-9_]{8,}|AKIA[0-9A-Z]{16}' \
  "$root" --exclude-dir=.git --exclude='*.example' 2>/dev/null | grep -v tests/no-hardcodes; then
  printf 'FAIL: real secret pattern committed\n' >&2
  fail=1
fi

[[ "$fail" == "0" ]] || exit 1
printf 'PASS: installer fully dynamic (no IPs, no hardcoded users, no secrets)\n'
