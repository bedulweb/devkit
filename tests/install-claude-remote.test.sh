#!/usr/bin/env bash
# install-claude-remote.test.sh — static guards for the Claude remote client.
# Usage: bash tests/install-claude-remote.test.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/install-opencode-claude-remote.sh"
patch="$root/config/opencode/plugins/opencode-with-claude-remote.patch"
cfg="$root/config/opencode/opencode.jsonc"
installer="$root/scripts/install-opencode.sh"

[[ -x "$script" ]] || { echo "FAIL: $script missing or not executable" >&2; exit 1; }
[[ -s "$patch" ]] || { echo "FAIL: $patch missing or empty" >&2; exit 1; }
grep -q "CLAUDE_PROXY_REMOTE_URL" "$patch" || { echo "FAIL: patch lacks remote mode" >&2; exit 1; }

# no IP literals / hardcoded homes in the new script (no-hardcodes policy)
if grep -HEn '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$script"; then
  echo "FAIL: hardcoded IPv4 in $script (default URL must come from the template)" >&2; exit 1;
fi
if grep -HEn '/root/|/home/[a-z_]+' "$script" | grep -vE '\$HOME'; then
  echo "FAIL: hardcoded home dir in $script" >&2; exit 1;
fi

# template carries the anthropic provider (env-based apiKey) + plugin entry
grep -q '"anthropic"' "$cfg" || { echo "FAIL: template lacks anthropic provider" >&2; exit 1; }
grep -q '"opencode-with-claude"' "$cfg" || { echo "FAIL: template lacks plugin entry" >&2; exit 1; }

# installer renders conditionally + calls the new script
grep -q "install-opencode-claude-remote.sh" "$installer" || { echo "FAIL: $installer does not call the claude-remote script" >&2; exit 1; }
grep -q "opencode-with-claude" "$installer" || { echo "FAIL: $installer has no seed-absent render rule" >&2; exit 1; }

echo "PASS: claude-remote installer wired (script+patch+template+render)"
