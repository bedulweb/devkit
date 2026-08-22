#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/install.sh"
devkit_cli="$root/scripts/devkit"

require() {
  local pattern="$1" file="$2" description="$3"
  if ! grep -qF "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    exit 1
  fi
}

require 'install_wrangler() {' "$installer" 'install.sh defines the Wrangler installer'
require 'bun add --global wrangler' "$installer" 'Wrangler is installed globally with Bun'
require 'install_wrangler' "$installer" 'the default tool-installation path invokes the Wrangler installer'
require 'wrangler' "$devkit_cli" 'devkit doctor reports the Wrangler CLI'

python3 - "$installer" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
start = text.index('if [[ "$PROFILE" != "minimal" ]]; then')
end = text.index('\n  fi', start)
default_block = text[start:end]
assert 'install_wrangler' in default_block, 'Wrangler must be installed by default and full profiles'
PY

printf 'PASS: Wrangler is part of the default devkit setup\n'
