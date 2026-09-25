#!/usr/bin/env bash
# Regression: the opencode.service unit produced by install-opencode.sh must be
# able to start `npx`-launched MCP servers, and must not hot-loop.
#
# Two silent failures motivated this:
#   1. The unit PATH omitted nvm's node bin, so `npx` was unreachable and MCP
#      servers declared with an npx command (agentation) never spawned — the
#      only symptom was an INFO line in the journal and missing tools.
#   2. `Restart=always` on a singleton ExecStart: `opencode serve --service`
#      exits 0 immediately when another instance owns the service, producing a
#      tight restart loop.
# A third, related: a pre-existing bare service must be stopped, or it keeps
# winning the singleton race and answers with empty {env:} provider keys (401).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/scripts/install-opencode.sh"

require() {
  grep -qF "$1" "$installer" || { echo "FAIL: $2" >&2; exit 1; }
}

# 1. nvm node bin resolved into the unit PATH
require '.nvm/versions/node/v*/bin' "installer does not resolve the nvm node bin"
require 'unit PATH includes nvm node bin' "installer does not report the nvm path"
# 2. no hot loop
if grep -q '^Restart=always' "$installer"; then
  echo "FAIL: Restart=always re-introduces the singleton restart loop" >&2
  exit 1
fi
require 'Restart=on-failure' "unit does not use Restart=on-failure"
# 3. unit staleness is tracked by a generation marker, not a PATH substring
require '# UNIT_GEN=2' "unit has no generation marker (stale units will not refresh)"
if grep -q 'grep -q ".local/share/vite-plus/bin"' "$installer"; then
  echo "FAIL: unit refresh still keyed on a PATH substring; use UNIT_GEN" >&2
  exit 1
fi
# 4. pre-existing bare service is cleared first
require 'stop_bare_service()' "installer has no stop_bare_service helper"
require 'PINKGREEN_API_KEY=' "stop_bare_service does not distinguish bare vs Doppler-backed"
grep -q '^  stop_bare_service$' "$installer" || {
  echo "FAIL: install_systemd_service never calls stop_bare_service" >&2
  exit 1
}
# 5. hindsight is optional and must not leave a dangling plugin path
require '.hindsight/coding-agents/index.js' "installer does not presence-check the hindsight plugin"
require 'omitted from opencode.jsonc plugins' "installer does not warn about the omitted plugin"

echo "PASS: opencode.service unit resolves nvm, uses on-failure, clears bare services"
