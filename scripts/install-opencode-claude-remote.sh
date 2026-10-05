#!/usr/bin/env bash
# install-opencode-claude-remote.sh — OpenCode (client) → Claude Max via
# remote Meridian proxy over Tailscale. No local `claude auth login` needed.
#
#   bash ~/linux-devkit/scripts/install-opencode-claude-remote.sh
#   CLAUDE_PROXY_REMOTE_URL=http://<proxy-host>:3456 bash ~/linux-devkit/scripts/install-opencode-claude-remote.sh
#   bash ~/linux-devkit/scripts/install-opencode-claude-remote.sh --test-chat
#
# What it does (idempotent):
#   1. checks Tailscale is connected and the remote proxy answers /health
#      (warnings only — config is still written when the proxy is down, so a
#      fresh VM is ready before the proxy host comes online)
#   2. clones/updates opencode-with-claude, applies the remote-mode patch
#      (config/opencode/plugins/opencode-with-claude-remote.patch — upstream
#      has no CLAUDE_PROXY_REMOTE_URL support), builds it, and seeds
#      ~/.cache/opencode/node_modules/opencode-with-claude (the path OpenCode
#      resolves the bare "opencode-with-claude" plugins entry to)
#   3. writes CLAUDE_PROXY_REMOTE_URL + CLAUDE_PROXY_API_KEY=dummy to
#      ~/.config/opencode/.env (loaded by the opencode service into the
#      plugin's process env — never a secret, safe on disk)
#   4. ensures the rendered opencode.jsonc has the "opencode-with-claude"
#      plugins entry (uncommented, seed now present) and the anthropic
#      provider block, then restarts the background service so the plugin
#      loads with session headers (new lineage → cold cache → HTTP 402 on
#      long requests without them)
#
# Env overrides:
#   CLAUDE_PROXY_REMOTE_URL (default: anthropic baseURL from the template)
#   CLAUDE_PLUGIN_REPO      (default: upstream opencode-with-claude)
#   CLAUDE_PLUGIN_REF       (default: main)
#   CLAUDE_PLUGIN_BUILD_DIR (default: $HOME/projects/apps/opencode-with-claude)
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$KIT/config/opencode/opencode.jsonc"
TARGET="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.jsonc}"
ENV_FILE="$HOME/.config/opencode/.env"
PATCH="$KIT/config/opencode/plugins/opencode-with-claude-remote.patch"
PLUGIN_NAME="opencode-with-claude"
SEED="$HOME/.cache/opencode/node_modules/$PLUGIN_NAME"
BUILD_DIR="${CLAUDE_PLUGIN_BUILD_DIR:-$HOME/projects/apps/opencode-with-claude}"
REPO="${CLAUDE_PLUGIN_REPO:-https://github.com/bedulweb/opencode-with-claude}"
REF="${CLAUDE_PLUGIN_REF:-v1.11.1-remote.1}"
TEST_CHAT=0
[[ "${1:-}" == "--test-chat" ]] && TEST_CHAT=1

log()  { printf '\033[1;36m==> claude-remote:\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Default remote URL comes from the template (keeps this script free of
# hardcoded hosts — see tests/no-hardcodes.test.sh).
default_url() {
  python3 - "$TEMPLATE" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
text = '\n'.join(l for l in raw.splitlines() if not l.lstrip().startswith('//'))
print(json.loads(text)['providers']['anthropic']['settings']['baseURL'])
PY
}
REMOTE_URL="${CLAUDE_PROXY_REMOTE_URL:-$(default_url)}"
REMOTE_URL="${REMOTE_URL%/}"
# Bare proxy root (no /v1) for ping + /health; the plugin strips a trailing
# /v1 itself, so either form works for CLAUDE_PROXY_REMOTE_URL.
REMOTE_ROOT="${REMOTE_URL%/v1}"
REMOTE_ROOT="${REMOTE_ROOT%/}"
export CLAUDE_PROXY_REMOTE_URL="$REMOTE_URL"
REMOTE_HOST="$(printf '%s' "$REMOTE_ROOT" | sed -E 's|^https?://||; s|[:/].*$||')"

# ── 0. prerequisites ────────────────────────────────────────────────
for bin in git node npm python3 curl; do
  have "$bin" || die "$bin missing (node via nvm; git/curl via apt)"
done
have opencode || die "opencode not found — run install-opencode.sh first"
have tailscale || die "tailscale not found — run install-tailscale.sh first"
[[ -f "$PATCH" ]] || die "remote patch missing: $PATCH"
[[ -f "$TARGET" ]] || die "opencode config missing: $TARGET — run install-opencode.sh first"
ok "tools present (git/node/npm/python3/curl/opencode/tailscale)"

# ── 1. Tailscale + remote health (warnings only) ────────────────────
if tailscale status >/dev/null 2>&1; then
  ok "tailscale connected"
  if tailscale ping --c=2 "$REMOTE_HOST" 2>&1 | grep -q "^pong"; then
    ok "ping $REMOTE_HOST"
  else
    warn "tailscale ping $REMOTE_HOST failed — proxy host may be offline (continuing)"
  fi
else
  warn "tailscale not connected — run install-tailscale.sh with a key (continuing)"
fi
if curl -m 10 -sS "$REMOTE_ROOT/health" 2>/dev/null | grep -q '"status":"healthy"'; then
  ok "remote proxy healthy ($REMOTE_ROOT/health)"
else
  warn "remote proxy not answering $REMOTE_ROOT/health (continuing — config still written)"
fi

# ── 2. clone/update + patch + build + seed ──────────────────────────
if [[ -d "$BUILD_DIR/.git" ]]; then
  log "updating plugin repo ($BUILD_DIR)"
  git -C "$BUILD_DIR" fetch origin >/dev/null 2>&1 || warn "git fetch failed — using local checkout"
  git -C "$BUILD_DIR" checkout -q "$REF" 2>/dev/null || warn "ref $REF missing — staying on current branch"
  git -C "$BUILD_DIR" pull --ff-only >/dev/null 2>&1 || true
else
  log "cloning plugin repo ($REF)"
  git clone --depth 1 --branch "$REF" "$REPO" "$BUILD_DIR" \
    || die "clone failed — check network and $REPO"
fi
if grep -q "CLAUDE_PROXY_REMOTE_URL" "$BUILD_DIR/src/index.ts" 2>/dev/null; then
  ok "remote mode already in source (upstream?) — patch skipped"
elif git -C "$BUILD_DIR" apply --check "$PATCH" 2>/dev/null; then
  git -C "$BUILD_DIR" apply "$PATCH" && ok "remote patch applied"
else
  die "patch does not apply cleanly — refresh it: git diff > $PATCH"
fi
log "building plugin (npm install + build)"
(cd "$BUILD_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1) \
  || die "npm install failed in $BUILD_DIR"
(cd "$BUILD_DIR" && npm run build >/dev/null 2>&1) \
  || die "npm run build failed in $BUILD_DIR"
grep -q "CLAUDE_PROXY_REMOTE_URL" "$BUILD_DIR/dist/index.js" \
  || die "built dist lacks remote mode"
(cd "$BUILD_DIR" && npm prune --omit=dev >/dev/null 2>&1 || true)
ok "built $(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)"
log "seeding OpenCode plugin cache ($SEED)"
rm -rf "$SEED"
mkdir -p "$SEED"
cp -f "$BUILD_DIR/package.json" "$BUILD_DIR/package-lock.json" "$SEED/" 2>/dev/null || cp -f "$BUILD_DIR/package.json" "$SEED/"
cp -rf "$BUILD_DIR/dist" "$SEED/"
cp -rf "$BUILD_DIR/node_modules" "$SEED/"
grep -q "CLAUDE_PROXY_REMOTE_URL" "$SEED/dist/index.js" || die "seeded dist lacks remote mode"
ok "seed ready"

# ── 3. runtime env file (service + CLI read this; values are not secret) ──
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"
set_kv() {  # set_kv KEY VALUE FILE — idempotent, preserves other lines
  local key="$1" val="$2" file="$3" tmp
  tmp="$(mktemp)"
  grep -v "^${key}=" "$file" 2>/dev/null >"$tmp" || true
  printf '%s=%s\n' "$key" "$val" >>"$tmp"
  mv "$tmp" "$file"
}
set_kv CLAUDE_PROXY_REMOTE_URL "$REMOTE_URL" "$ENV_FILE"
set_kv CLAUDE_PROXY_API_KEY "dummy" "$ENV_FILE"
chmod 600 "$ENV_FILE"
export CLAUDE_PROXY_API_KEY="dummy"
ok ".env carries CLAUDE_PROXY_REMOTE_URL + CLAUDE_PROXY_API_KEY=dummy"

# ── 4. rendered config: plugin entry + anthropic provider ───────────
# Rewrite the plugins array canonically (tolerant of trailing commas and
# commented-out entries, which strict JSON rejects but OpenCode accepts).
python3 - "$TARGET" "$REMOTE_URL" <<'PY'
import json, re, sys
path, url = sys.argv[1], sys.argv[2]
raw = open(path).read()
m = re.search(r'"plugins"\s*:\s*\[(.*?)\]', raw, re.S)
assert m, 'plugins array not found'
inner_lines = m.group(1).splitlines()
comments = [l for l in inner_lines if l.lstrip().startswith('//')]
inner = '\n'.join(l for l in inner_lines
                  if not l.lstrip().startswith('//'))
entries = re.findall(r'"([^"]*)"', inner)
if 'opencode-with-claude' not in entries:
    entries.append('opencode-with-claude')
    print('plugins entry added')
else:
    print('plugins entry present')
new_block = '"plugins": [\n'
for c in comments:
    new_block += c + '\n'
new_block += ''.join('    "%s",\n' % e for e in entries)
new_block = new_block.rstrip(',\n') + '\n  ]'
raw = raw[:m.start()] + new_block + raw[m.end():]
open(path, 'w').write(raw)
# normalize baseURL to the active remote (template default vs env override)
text = '\n'.join(l for l in raw.splitlines() if not l.lstrip().startswith('//'))
cfg = json.loads(text)
base = cfg['providers']['anthropic']['settings']['baseURL']
want = url if url.rstrip('/').endswith('/v1') else url.rstrip('/') + '/v1'
if base.rstrip('/') != want.rstrip('/'):
    raw = raw.replace(base, want)
    open(path, 'w').write(raw)
    print('anthropic baseURL normalized')
else:
    print('anthropic baseURL ok')
PY
python3 - "$TARGET" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
text = '\n'.join(l for l in raw.splitlines() if not l.lstrip().startswith('//'))
cfg = json.loads(text)
assert 'opencode-with-claude' in cfg['plugins'], 'plugin entry missing'
assert cfg['providers']['anthropic']['settings']['apiKey'], 'anthropic apiKey missing'
print('config valid: plugin + anthropic provider present')
PY

# ── 5. restart service so the plugin loads, then verify ─────────────
log "restarting background service (loads plugin)"
if opencode service restart >/dev/null 2>&1; then
  ok "service restarted"
  sleep 3
else
  warn "service restart failed — try: systemctl --user restart opencode.service"
fi
if opencode plugin list 2>/dev/null | grep -q "opencode-with-claude"; then
  ok "plugin list shows opencode-with-claude"
else
  warn "plugin not in list yet — service may need a moment: opencode service restart"
fi
if curl -m 10 -sS "$REMOTE_ROOT/health" 2>/dev/null | grep -q '"status":"healthy"'; then
  ok "remote proxy healthy"
  if [[ "$TEST_CHAT" == "1" ]]; then
    log "sending test chat (anthropic/claude-sonnet-5-5)"
    if opencode run --model anthropic/claude-sonnet-5-5 "Balas hanya dengan satu kata: OK" 2>&1 | tail -2; then
      ok "test chat done — check output above for OK (not billing_error)"
    fi
  else
    log "skip test chat (pass --test-chat to send one)"
  fi
else
  warn "remote proxy down — chat will fail until it is back (config is ready)"
fi

log "done: opencode → Claude Max via $REMOTE_URL (no local login needed)"
