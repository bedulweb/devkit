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
for s in ['exa', 'firecrawl', 'linear']:
    assert s in servers, f'mcp server {s} missing'
print('PASS: opencode.jsonc valid (providers=%s mcp=%s)' % (sorted(cfg['providers']), sorted(servers)))
PY

# 6. installer must not contain hardcoded secrets either
if grep -rEn '(sk-[A-Za-z0-9_-]{8,}|fc-[A-Za-z0-9]{10,}|Mastah123)' "$cfg" "$installer" | grep -v 'check-opencode-config'; then
  echo "FAIL: hardcoded secret in opencode files" >&2
  exit 1
fi

# 7. installer loads all required keys from Doppler
for k in PINKGREEN_API_KEY ROUTEID_API_KEY EXA_API_KEY FIRECRAWL_API_KEY; do
  grep -q "load_secret $k" "$installer" || { echo "FAIL: $installer does not load $k" >&2; exit 1; }
done

echo "PASS: install-opencode.sh loads secrets from Doppler"
