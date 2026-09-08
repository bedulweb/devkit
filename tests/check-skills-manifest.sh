#!/usr/bin/env bash
# Fail if skills-manifest.txt drifts from scripts/install-skills.sh SOURCES.
# Usage: bash tests/check-skills-manifest.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/install-skills.sh"
manifest="$root/skills-manifest.txt"
fail=0

in_block=0
while IFS= read -r line; do
  if [[ "$line" == *"SOURCES=("* ]]; then in_block=1; continue; fi
  if [[ "$in_block" == "1" && "$line" == ")"* ]]; then in_block=0; continue; fi
  [[ "$in_block" == "1" ]] || continue
  [[ "$line" =~ ^[[:space:]]*\"([^\"]+)\" ]] || continue
  entry="${BASH_REMATCH[1]}"
  [[ "$entry" == *"|"* ]] || continue
  IFS='|' read -r src skill _label ref <<<"$entry"
  want="$src"
  [[ -n "${ref:-}" ]] && want="${src}#${ref}"
  if ! grep -qF -- "$want" "$manifest"; then
    printf 'FAIL: manifest missing pinned source: %s\n' "$want" >&2; fail=1
  fi
  want_skill="--skill $skill"
  [[ "$skill" == "STAR" ]] && want_skill="--skill *"
  # check on the manifest line(s) mentioning this source
  if ! grep -F -- "$src" "$manifest" | grep -qF -- "$want_skill"; then
    printf 'FAIL: manifest missing "%s" for %s\n' "$want_skill" "$src" >&2; fail=1
  fi
done < "$script"

if [[ "$fail" == "0" ]]; then
  printf 'PASS: skills-manifest.txt matches SOURCES (%s entries)\n' \
    "$(grep -c '^  "' "$script" || true)"
else
  printf 'FAIL: manifest drift detected\n' >&2
fi
exit "$fail"
