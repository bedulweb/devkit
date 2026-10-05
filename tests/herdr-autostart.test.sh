#!/usr/bin/env bash
# ensure_herdr_autostart: SSH login → exec herdr, tanpa loop di dalam pane
# herdr, tanpa ganggu shell non-interaktif (run.sh, scp), idempotent.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmphome="$(mktemp -d)"
trap 'rm -rf "$tmphome"' EXIT

fn="$(sed -n '/^ensure_herdr_autostart() {$/,/^}$/p' "$root/install.sh")"
[[ -n "$fn" ]] || { echo "FAIL: ensure_herdr_autostart not found" >&2; exit 1; }

run_fn() {
  HOME="$tmphome" WITH_HERDR="${WITH_HERDR:-1}" bash -c "ok(){ :; }; $fn; ensure_herdr_autostart"
}

printf 'echo existing\n' >"$tmphome/.bashrc"
run_fn
run_fn
echo 'export AFTER=1' >>"$tmphome/.bashrc"
run_fn
n="$(grep -c '>>> linux-devkit herdr-autostart >>>' "$tmphome/.bashrc")"
[[ "$n" == 1 ]] || { echo "FAIL: block count $n" >&2; exit 1; }
tail -n1 "$tmphome/.bashrc" | grep -q '<<< linux-devkit herdr-autostart <<<' \
  || { echo "FAIL: block not last" >&2; exit 1; }
echo "PASS: idempotent, block stays last"

# fake herdr di PATH
mkdir -p "$tmphome/bin"
printf '#!/bin/sh\necho HERDR_LAUNCHED\n' >"$tmphome/bin/herdr"
chmod +x "$tmphome/bin/herdr"
src() { env -i HOME="$tmphome" PATH="$tmphome/bin:/usr/bin:/bin" "$@" bash -ic '. "$HOME/.bashrc"; echo SHELL_KEPT' 2>/dev/null; }

src SSH_TTY=/dev/pts/9 | grep -q HERDR_LAUNCHED || { echo "FAIL: ssh login did not launch herdr" >&2; exit 1; }
src SSH_TTY=/dev/pts/9 | grep -q SHELL_KEPT && { echo "FAIL: exec did not replace shell" >&2; exit 1; }
src SSH_TTY=/dev/pts/9 HERDR_ENV=1 | grep -q HERDR_LAUNCHED && { echo "FAIL: launched inside herdr pane" >&2; exit 1; }
src SSH_TTY=/dev/pts/9 NO_HERDR=1 | grep -q HERDR_LAUNCHED && { echo "FAIL: NO_HERDR ignored" >&2; exit 1; }
src | grep -q HERDR_LAUNCHED && { echo "FAIL: launched without SSH" >&2; exit 1; }
out="$(env -i HOME="$tmphome" PATH="$tmphome/bin:/usr/bin:/bin" SSH_TTY=/dev/pts/9 bash -c '. "$HOME/.bashrc"; echo SHELL_KEPT')"
[[ "$out" == *SHELL_KEPT* && "$out" != *HERDR_LAUNCHED* ]] || { echo "FAIL: non-interactive shell launched herdr" >&2; exit 1; }
echo "PASS: ssh → herdr; herdr pane / NO_HERDR / non-ssh / non-interactive skip"

DEVKIT_HERDR_AUTOSTART=0 HOME="$tmphome" WITH_HERDR=1 bash -c "ok(){ :; }; $fn; ensure_herdr_autostart"
grep -q 'herdr-autostart' "$tmphome/.bashrc" && { echo "FAIL: opt-out did not remove block" >&2; exit 1; }
echo "PASS: DEVKIT_HERDR_AUTOSTART=0 removes block"
