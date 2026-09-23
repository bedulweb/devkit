#!/usr/bin/env bash
# Fail if config/opencode/opencode.jsonc is invalid or leaks secrets.
# Usage: bash tests/check-opencode-config.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfg="$root/config/opencode/opencode.jsonc"
installer="$root/scripts/install-opencode.sh"

[[ -f "$cfg" ]] || { echo "FAIL: $cfg missing" >&2; exit 1; }
[[ -x "$installer" ]] || { echo "FAIL: $installer missing or not executable" >&2; exit 1; }

python3 - "$cfg" <<'PY'
import json, re, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text()
# 1. no hardcoded secrets (placeholders like sk-xxx docs are not allowed here)
for pat in [r'sk-[A-Za-z0-9_-]{8,}', r'fc-[A-Za-z0-9]{8,}', r'Mastah123', r'dp\.st\.[A-Za-z0-9]{8,}', r'github_pat_[A-Za-z0-9_]{8,}']:
    m = re.search(pat, raw)
    assert not m, f'possible hardcoded secret: {m.group(0)[:12]}…'
# 2. valid JSONC (strip full-line // comments only — URLs contain //)
text = '\n'.join(l for l in raw.splitlines() if not l.lstrip().startswith('//'))
cfg = json.loads(text)
# 3. required providers + models
assert 'cx' in cfg['providers'], 'provider cx missing'
assert 'routeid' in cfg['providers'], 'provider routeid missing'
assert 'cx/gpt-5.6-luna' in json.dumps(cfg['providers']['cx']), 'cx luna model missing'
# 4. every apiKey must be an {env:} reference, never a literal
for pname, p in cfg['providers'].items():
    key = (p.get('settings') or {}).get('apiKey', '')
    if key:
        assert key.startswith('{env:'), f'provider {pname}: apiKey must use {{env:}} (got {key[:12]}…)'
# 5. required MCP servers
servers = cfg.get('mcp', {}).get('servers', {})
for s in ['exa', 'firecrawl', 'linear', 'neon']:
    assert s in servers, f'mcp server {s} missing'
print('PASS: opencode.jsonc valid (providers=%s mcp=%s)' % (sorted(cfg['providers']), sorted(servers)))
PY

# 5b. V2 server plugins: hindsight entry (placeholder rendered at install)
python3 - "$cfg" <<'PY'
import json, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text()
text = '\n'.join(l for l in raw.splitlines() if not l.lstrip().startswith('//'))
cfg = json.loads(text)
plugins = cfg.get('plugins', [])
assert any('HINDSIGHT_PLUGIN_DIR' in p for p in plugins), 'plugins must reference __HINDSIGHT_PLUGIN_DIR__'
print('PASS: plugins entry present (%s)' % plugins)
PY

# 6. installer must not contain hardcoded secrets either
if grep -rEn '(sk-[A-Za-z0-9_-]{8,}|fc-[A-Za-z0-9]{10,}|Mastah123)' "$cfg" "$installer" "$root/scripts/install-opencode-plugins.sh" "$root/config/opencode/plugins/opencode-firecrawl/index.ts" | grep -v 'check-opencode-config'; then
  echo "FAIL: hardcoded secret in opencode files" >&2
  exit 1
fi

# 6b. vendored firecrawl V2 plugin must exist and stay runtime-dependency-free
# (the compiled opencode binary cannot resolve `@opencode/plugin` from plugin
# dirs — only type-only imports are allowed).
VENDOR="$root/config/opencode/plugins/opencode-firecrawl"
for f in index.ts package.json tsconfig.json skills/firecrawl-cli/SKILL.md skills/firecrawl-cli/rules/install.md; do
  [[ -f "$VENDOR/$f" ]] || { echo "FAIL: vendored firecrawl plugin missing $f" >&2; exit 1; }
done
if grep -nE "^import .*@opencode/plugin" "$VENDOR/index.ts" | grep -v 'import type'; then
  echo "FAIL: vendored plugin has runtime @opencode/plugin import (must be import type)" >&2
  exit 1
fi
[[ -x "$root/scripts/install-opencode-plugins.sh" ]] || { echo "FAIL: install-opencode-plugins.sh missing or not executable" >&2; exit 1; }
grep -q "install-opencode-plugins.sh" "$installer" || { echo "FAIL: $installer does not call install-opencode-plugins.sh" >&2; exit 1; }
grep -q "__HINDSIGHT_PLUGIN_DIR__" "$installer" || { echo "FAIL: $installer does not render __HINDSIGHT_PLUGIN_DIR__" >&2; exit 1; }
echo "PASS: vendored firecrawl plugin + plugins installer wired"

# 7. installer loads all required keys from Doppler
for k in PINKGREEN_API_KEY ROUTEID_API_KEY EXA_API_KEY FIRECRAWL_API_KEY; do
  grep -q "load_secret $k" "$installer" || { echo "FAIL: $installer does not load $k" >&2; exit 1; }
done

echo "PASS: install-opencode.sh loads secrets from Doppler"
