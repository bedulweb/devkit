#!/usr/bin/env bash
# install-opencode-plugins.sh — ensure OpenCode V2 server plugins work.
#
#   bash ~/linux-devkit/scripts/install-opencode-plugins.sh
#
# Manages:
#   1. opencode-firecrawl — vendored V2 port at
#      ~/linux-devkit/config/opencode/plugins/opencode-firecrawl, synced to
#      ~/.config/opencode/plugins/opencode-firecrawl (auto-discovered).
#      Upstream (github.com/firecrawl/opencode-firecrawl) is V1-only and its
#      `@opencode/plugin` runtime import fails to resolve inside the compiled
#      opencode binary — the vendored copy uses a type-only import instead.
#   2. hindsight-coding-agents — expected at ~/.hindsight/coding-agents
#      (installed by its own installer); referenced from opencode.jsonc
#      "plugins" via the __HINDSIGHT_PLUGIN_DIR__ placeholder.
#   3. firecrawl-cli — installed globally when missing.
#
# Secrets are never stored here. The firecrawl plugin resolves
# FIRECRAWL_API_KEY from env, falling back to Doppler
# (developer-workstation/dev) at plugin setup time.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_PLUGINS="${HOME}/.config/opencode/plugins"
VENDOR_DIR="$KIT/config/opencode/plugins/opencode-firecrawl"
TARGET_FIRECRAWL="$TARGET_PLUGINS/opencode-firecrawl"
HINDSIGHT_DIR="${HOME}/.hindsight/coding-agents"

DOPPLER_PROJECT="${DEVKIT_OPENCODE_DOPPLER_PROJECT:-${DEVKIT_CODEX_DOPPLER_PROJECT:-developer-workstation}}"
DOPPLER_CONFIG="${DEVKIT_OPENCODE_DOPPLER_CONFIG:-${DEVKIT_CODEX_DOPPLER_CONFIG:-dev}}"

log()  { printf '\033[1;36m==> opencode-plugins:\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── 1. opencode-firecrawl (vendored V2 port) ──────────────────────────
log "syncing vendored opencode-firecrawl plugin"
[[ -f "$VENDOR_DIR/index.ts" ]] || { echo "  ✗ vendored plugin missing: $VENDOR_DIR" >&2; exit 1; }
mkdir -p "$TARGET_PLUGINS"
# Full replace so stale files (upstream .git, node_modules) never linger.
rm -rf "$TARGET_FIRECRAWL"
mkdir -p "$TARGET_FIRECRAWL"
cp -f "$VENDOR_DIR/index.ts" "$VENDOR_DIR/package.json" "$VENDOR_DIR/tsconfig.json" \
  "$VENDOR_DIR/README.md" "$VENDOR_DIR/LICENSE" "$TARGET_FIRECRAWL/"
rm -rf "$TARGET_FIRECRAWL/skills"
cp -r "$VENDOR_DIR/skills" "$TARGET_FIRECRAWL/skills"
ok "synced → $TARGET_FIRECRAWL"

# ── 2. firecrawl-cli ──────────────────────────────────────────────────
if have firecrawl; then
  ok "firecrawl-cli $(firecrawl --version 2>/dev/null | head -1)"
else
  log "installing firecrawl-cli"
  if npm install -g firecrawl-cli >/dev/null 2>&1; then
    ok "firecrawl-cli $(firecrawl --version 2>/dev/null | head -1)"
  else
    warn "firecrawl-cli install failed — run manually: npm install -g firecrawl-cli"
  fi
fi

# ── 3. hindsight-coding-agents (presence check only) ──────────────────
if [[ -f "$HINDSIGHT_DIR/index.js" ]]; then
  ok "hindsight plugin present ($HINDSIGHT_DIR)"
else
  warn "hindsight plugin missing at $HINDSIGHT_DIR"
  warn "install it first, then re-run install-opencode.sh to render the plugins entry:"
  warn "  bunx --yes @vectorize-io/hindsight-coding-agents@latest"
fi

# ── 4. verify key source (value never printed) ────────────────────────
if [[ -n "${FIRECRAWL_API_KEY:-}" ]]; then
  ok "FIRECRAWL_API_KEY in env (plugin will use it directly)"
elif have doppler && doppler secrets get FIRECRAWL_API_KEY \
    --project="$DOPPLER_PROJECT" --config="$DOPPLER_CONFIG" --plain >/tmp/opencode-secret 2>/dev/null \
    && [[ -s /tmp/opencode-secret ]]; then
  rm -f /tmp/opencode-secret
  ok "FIRECRAWL_API_KEY in Doppler $DOPPLER_PROJECT/$DOPPLER_CONFIG (plugin falls back to it)"
  rm -f /tmp/opencode-secret
else
  rm -f /tmp/opencode-secret
  warn "FIRECRAWL_API_KEY not in env or Doppler — firecrawl calls will fail auth"
fi

# ── 5. verify loaded plugins (needs running server, warnings only) ───
if have opencode; then
  if opencode plugin list 2>/dev/null | grep -q "opencode-firecrawl"; then
    ok "plugin list shows opencode-firecrawl"
  else
    warn "opencode-firecrawl not in plugin list — restart service: opencode service restart"
  fi
  if [[ -f "$HINDSIGHT_DIR/index.js" ]]; then
    if opencode api get /api/plugin 2>/dev/null | grep -q "hindsight"; then
      ok "hindsight plugin active in server"
    else
      warn "hindsight not active — restart service: opencode service restart"
    fi
  fi
fi

log "done"
