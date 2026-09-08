#!/usr/bin/env bash
set -euo pipefail
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_CONFIG="$CODEX_HOME/config.toml"
CODEX_CATALOG="$CODEX_HOME/cx-models.json"
PINKGREEN_URL="${PINKGREEN_BASE_URL:-https://ai.pinkgreen.me/v1}"
log() { printf '==> codex: %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
mkdir -p "$CODEX_HOME"
if ! have npm; then echo "npm is required before Codex installation" >&2; exit 1; fi
if ! have jq; then echo "jq is required to build the Codex model catalog" >&2; exit 1; fi
log "installing @openai/codex"
npm install --global @openai/codex
log "building cx model catalog"
codex debug models > /tmp/codex-models.json
jq '{models: [.models[] | select(.slug == "gpt-5.6-sol" or .slug == "gpt-5.6-terra" or .slug == "gpt-5.6-luna" or .slug == "gpt-6-astra") | .slug = (if .slug == "gpt-6-astra" then "cx/gpt-6-astra" else (.slug | sub("^gpt-"; "cx/gpt-")) end)]}' /tmp/codex-models.json > "$CODEX_CATALOG"
chmod 600 "$CODEX_CATALOG"
touch "$CODEX_CONFIG"
python3 - "$CODEX_CONFIG" "$PINKGREEN_URL" "$CODEX_CATALOG" <<'PY'
from pathlib import Path
import re
import sys
path, base_url, catalog = sys.argv[1:]
text = Path(path).read_text()
for key, value in {"model": '"cx/gpt-5.6-luna"', "model_provider": '"openai"', "openai_base_url": repr(base_url), "model_catalog_json": repr(catalog)}.items():
    line = f"{key} = {value}"
    pattern = rf"(?m)^{re.escape(key)}\s*=.*$"
    text = re.sub(pattern, line, text, count=1) if re.search(pattern, text) else line + "\n" + text
servers = '''
# >>> pinkgreen-codex-mcp >>>
[mcp_servers.exa]
command = "bunx"
args = ["-y", "exa-mcp-server"]
[mcp_servers.firecrawl-mcp]
command = "bunx"
args = ["-y", "firecrawl-mcp"]
[mcp_servers.framelink]
command = "bunx"
args = ["-y", "figma-developer-mcp", "--stdio"]
enabled = false
[mcp_servers.assistant-ui]
command = "bunx"
args = ["-y", "@assistant-ui/mcp-docs-server"]
enabled = false
[mcp_servers.hugeicons]
command = "bunx"
args = ["-y", "@hugeicons/mcp-server"]
enabled = false
# <<< pinkgreen-codex-mcp <<<
'''
if "# >>> pinkgreen-codex-mcp >>>" not in text:
    text += servers
Path(path).write_text(text)
PY
for name in sol terra luna astra; do
  case "$name" in
    sol) model="cx/gpt-5.6-sol"; effort="medium" ;;
    terra) model="cx/gpt-5.6-terra"; effort="medium" ;;
    luna) model="cx/gpt-5.6-luna"; effort="xhigh" ;;
    astra) model="cx/gpt-6-astra"; effort="medium" ;;
  esac
  cat > "$CODEX_HOME/$name.config.toml" <<EOF
model = "$model"
model_provider = "openai"
model_reasoning_effort = "$effort"
EOF
  chmod 600 "$CODEX_HOME/$name.config.toml"
done
chmod 600 "$CODEX_CONFIG"
codex --strict-config --profile terra --help >/dev/null
codex debug models | jq -r '.models[].slug' | grep -E '^cx/'
log "ready: /model can switch between cx/* models"
