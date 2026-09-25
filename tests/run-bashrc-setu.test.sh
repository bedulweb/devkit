#!/usr/bin/env bash
# Regression: run.sh must not source ~/.bashrc while `set -u` is active.
#
# The stock Ubuntu .bashrc opens with `[ -z "$PS1" ] && return`. In a
# non-interactive shell running `set -euo pipefail`, expanding the unset PS1
# does not merely return non-zero — bash aborts the shell outright, so the
# `|| true` that followed the source never got a chance to run. That silently
# ended run.sh immediately after install.sh, skipping every later step
# (GitHub auth, restore, skills, deps, verify) while install.sh looked fine.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run="$root/run.sh"

tmphome="$(mktemp -d)"
trap 'rm -rf "$tmphome"' EXIT
# the first real line of a stock Ubuntu .bashrc
printf '[ -z "$PS1" ] && return\n' >"$tmphome/.bashrc"

# 1. behavioural precondition: the unguarded pattern really does abort
if bash -c 'set -euo pipefail; . "$1/.bashrc" 2>/dev/null || true; echo REACHED_END' _ "$tmphome" \
     | grep -q REACHED_END; then
  echo "FAIL: unguarded .bashrc source no longer aborts — re-check this test" >&2
  exit 1
fi
echo "PASS: unguarded .bashrc source aborts a set -euo shell (precondition holds)"

# 2. the guarded pattern survives
out="$(bash -c 'set -euo pipefail; set +eu; . "$1/.bashrc" >/dev/null 2>&1 || true; set -eu; echo REACHED_END' _ "$tmphome")"
[[ "$out" == "REACHED_END" ]] || { echo "FAIL: guarded source still aborts: $out" >&2; exit 1; }
echo "PASS: set +eu guard lets the script continue"

# 3. run.sh must actually use that guard, and keep sourcing .bashrc
grep -q 'set +eu' "$run" || {
  echo "FAIL: run.sh does not relax -e/-u around the .bashrc source" >&2
  exit 1
}
grep -q '\. "\$HOME/\.bashrc"' "$run" || {
  echo "FAIL: run.sh no longer sources ~/.bashrc" >&2
  exit 1
}
echo "PASS: run.sh guards the .bashrc source"
