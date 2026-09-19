#!/usr/bin/env bash
# install-opencode.sh — Install OpenCode binary + custom models + MCP (Doppler-backed).
# Mirrors install-codex.sh / install-omp.sh: no raw API key is stored in this repo.
# Secrets live in Doppler (default: developer-workstation/dev) and resolve at
# runtime via {env:VAR} placeholders in opencode.jsonc.
#
#   bash ~/linux-devkit/scripts/install-opencode.sh
#
# Result: ~/.config/opencode/opencode.jsonc (chmod 600)
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$KIT/config/opencode/opencode.jsonc"
TARGET="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.jsonc}"
LOCAL_BIN="${HOME}/.local/bin"

DOPPLER_PROJECT="${DEVKIT_OPENCODE_DOPPLER_PROJECT:-${DEVKIT_CODEX_DOPPLER_PROJECT:-developer-workstation}}"
DOPPLER_CONFIG="${DEVKIT_OPENCODE_DOPPLER_CONFIG:-${DEVKIT_CODEX_DOPPLER_CONFIG:-dev}}"

log()  { printf '\033[1;36m==> opencode:\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── Load secrets from Doppler (verify presence, never write values to disk) ──
load_secret() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then return 0; fi
  if have doppler && doppler secrets get "$name" \
      --project="$DOPPLER_PROJECT" --config="$DOPPLER_CONFIG" --plain >/tmp/opencode-secret 2>/dev/null; then
    export "$name=$(tr -d '\r\n' </tmp/opencode-secret)"
    rm -f /tmp/opencode-secret
  fi
}

log "loading secrets from Doppler ($DOPPLER_PROJECT/$DOPPLER_CONFIG)"
load_secret PINKGREEN_API_KEY
load_secret ROUTEID_API_KEY
load_secret EXA_API_KEY
load_secret FIRECRAWL_API_KEY
# legacy alias: older configs used SABER_API_KEY for the same PinkGreen endpoint
if [[ -z "${PINKGREEN_API_KEY:-}" && -n "${SABER_API_KEY:-}" ]]; then
  export PINKGREEN_API_KEY="$SABER_API_KEY"
fi
if [[ -z "${OPENAI_API_KEY:-}" && -n "${PINKGREEN_API_KEY:-}" ]]; then
  export OPENAI_API_KEY="$PINKGREEN_API_KEY"
fi

missing=0
for k in PINKGREEN_API_KEY ROUTEID_API_KEY EXA_API_KEY FIRECRAWL_API_KEY; do
  if [[ -z "${!k:-}" ]]; then
    warn "$k not found in env or Doppler — related provider/MCP will fail at runtime"
    missing=1
  fi
done
[[ "$missing" == "0" ]] && ok "secrets present (values not printed)"

# ── Install OpenCode binary ─────────────────────────────────────────────
if have opencode; then
  ok "opencode $(opencode --version 2>/dev/null | head -1)"
else
  log "installing opencode"
  if curl -fsSL https://opencode.ai/install | bash; then
    export PATH="$HOME/.opencode/bin:$PATH"
    [[ -x "$HOME/.opencode/bin/opencode" ]] && ln -sf "$HOME/.opencode/bin/opencode" "$LOCAL_BIN/opencode" 2>/dev/null || true
    ok "opencode $(opencode --version 2>/dev/null | head -1 || echo installed)"
  else
    die "opencode install failed"
  fi
fi

# ── Render config (template has {env:} placeholders only — safe to copy) ──
[[ -f "$TEMPLATE" ]] || die "template missing: $TEMPLATE"
mkdir -p "$(dirname "$TARGET")"
if [[ -f "$TARGET" ]] && ! cmp -s "$TEMPLATE" "$TARGET"; then
  cp -f "$TARGET" "$TARGET.bak.$(date +%Y%m%d%H%M%S)"
  ok "existing config backed up"
fi
cp -f "$TEMPLATE" "$TARGET"
chmod 600 "$TARGET"
ok "config → $TARGET"

# ── Verify ──────────────────────────────────────────────────────────
python3 - "$TARGET" <<'PY'
import json, sys
from pathlib import Path
lines = [l for l in Path(sys.argv[1]).read_text().splitlines()
         if not l.lstrip().startswith('//')]
cfg = json.loads('\n'.join(lines))
assert 'cx' in cfg['providers'], 'provider cx missing'
assert 'routeid' in cfg['providers'], 'provider routeid missing'
assert 'exa' in cfg['mcp']['servers'], 'mcp exa missing'
assert 'firecrawl' in cfg['mcp']['servers'], 'mcp firecrawl missing'
assert 'agentation' in cfg['mcp']['servers'], 'mcp agentation missing'
print('config JSON valid: providers=%s mcp=%s' % (
  sorted(cfg['providers']), sorted(cfg['mcp']['servers'])))
PY

log "ready: run 'opencode' (keys resolve from env/Doppler at runtime)"
log "hint: source ~/linux-devkit/scripts/export-env.sh  # or: doppler run --project $DOPPLER_PROJECT --config $DOPPLER_CONFIG -- opencode"

# ── Seed managed background service with keys ─────────────────────────
# `opencode serve --service` is auto-spawned by the first CLI/TUI call and
# inherits env from THAT parent. If it was spawned from a shell without
# Doppler env, {env:} placeholders resolve empty and every inference fails
# with HTTP 401 — while curl from a key-loaded shell still returns 200.
# Bounce it here under `doppler run` so the running service holds the keys.
# No secret value is printed, logged, or written to disk in this step.
if have opencode && have doppler && [[ "$missing" == "0" ]]; then
  if doppler run --project="$DOPPLER_PROJECT" --config="$DOPPLER_CONFIG" -- \
      opencode service restart >/dev/null 2>&1; then
    ok "background service restarted with Doppler env"
    if doppler run --project="$DOPPLER_PROJECT" --config="$DOPPLER_CONFIG" -- \
        opencode api get /api/provider/cx 2>/dev/null | python3 -c '
import json, sys
key = json.load(sys.stdin)["data"]["settings"].get("apiKey", "")
assert key and "{env:" not in key, "key did not resolve"
print("provider cx key resolves in running service (%d chars)" % len(key))
'; then
      ok "provider keys resolve in running service"
    else
      warn "service restarted but cx key does not resolve — retry: doppler run --project $DOPPLER_PROJECT --config $DOPPLER_CONFIG -- opencode service restart"
    fi
  else
    warn "could not restart background service — run manually: doppler run --project $DOPPLER_PROJECT --config $DOPPLER_CONFIG -- opencode service restart"
  fi
else
  warn "skipping service restart (doppler/opencode missing or secrets incomplete)"
fi
