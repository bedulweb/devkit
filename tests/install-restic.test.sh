#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/install.sh"
restic_script="$root/scripts/install-restic.sh"
devkit_cli="$root/scripts/devkit"

require() {
  local pattern="$1" file="$2" description="$3"
  if ! grep -qF "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    exit 1
  fi
}

require 'install_restic() {' "$installer" 'install.sh defines the restic installer'
require 'install_restic' "$installer" 'the default tool-installation path invokes the restic installer'
require 'restic' "$devkit_cli" 'devkit doctor reports the restic CLI'
require '#!/usr/bin/env bash' "$restic_script" 'install-restic.sh is a shell script'
require 'drestic' "$restic_script" 'install-restic.sh installs the drestic Doppler wrapper'
require 'R2_ACCESS_KEY_ID' "$restic_script" 'drestic maps R2_* Doppler keys to AWS_* restic env'
require 'RESTIC_REPOSITORY' "$restic_script" 'drestic uses RESTIC_REPOSITORY from Doppler'
require 'RESTIC_PASSWORD' "$restic_script" 'drestic uses RESTIC_PASSWORD from Doppler'

# restic must be IP-agnostic: no hardcoded IPv4 literals in the installer
if grep -rEn '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$restic_script" "$installer" | grep -v '1\.0\.0\|0\.19\.1\|3\.32\.0\|3\.29\.0\|0\.40\.3\|0\.60\.3\|2\.96\.0\|14\.1\.1\|10\.2\.0\|2\.36\.0\|1\.7\.1\|1\.24' >/dev/null; then
  printf 'FAIL: hardcoded IP literal found in restic installer path\n' >&2
  grep -rEn '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$restic_script" "$installer" >&2 || true
  exit 1
fi

python3 - "$installer" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
# restic is in the always-block (before the `if [[ "$PROFILE" != "minimal" ]]`),
# so EVERY profile (any VPS, any IP) gets it — like gh/jq, not gated by profile.
always_end = text.index('if [[ "$PROFILE" != "minimal" ]]; then')
always_block = text[:always_end]
assert 'install_restic' in always_block, 'restic must be installed on all profiles (always-block)'
PY

printf 'PASS: restic is part of the default devkit setup (all profiles, IP-agnostic)\n'
