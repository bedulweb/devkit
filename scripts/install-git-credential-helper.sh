#!/usr/bin/env bash
# Install the Doppler-backed GitHub credential helper permanently for this user.
set -euo pipefail

kit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_dir="${DEVKIT_GIT_HELPER_DIR:-$HOME/.local/bin}"
helper_source="$kit_dir/scripts/git-credential-doppler.sh"
helper="$install_dir/git-credential-doppler"

mkdir -p "$install_dir"
install -m 755 "$helper_source" "$helper"

# Replace any gh helper for github.com, while leaving helpers for other hosts alone.
git config --global --replace-all credential.https://github.com.helper "$helper"

# Remove legacy devkit URL rewrites that embedded a GitHub token in ~/.gitconfig.
while IFS= read -r key; do
  [[ "$key" == url.https://x-access-token:*@github.com/.insteadOf ]] || continue
  git config --global --unset-all "$key" || true
done < <(
  git config --global --name-only --get-regexp '^url\.https://x-access-token:.*@github\.com/\.insteadOf$' 2>/dev/null || true
)

printf 'GitHub credential helper installed: %s\n' "$helper"
