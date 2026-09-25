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
load_secret CX_API_KEY
load_secret ROUTEID_API_KEY
load_secret EXA_API_KEY
load_secret FIRECRAWL_API_KEY
# NOTE: sentry/mobbin/linear/neon are OAuth-only (creds in opencode.db) —
# no manual Authorization header, no Doppler secret required.
# legacy alias: older configs used SABER_API_KEY for the same PinkGreen endpoint
if [[ -z "${PINKGREEN_API_KEY:-}" && -n "${SABER_API_KEY:-}" ]]; then
  export PINKGREEN_API_KEY="$SABER_API_KEY"
fi
if [[ -z "${PINKGREEN_API_KEY:-}" && -n "${CX_API_KEY:-}" ]]; then
  export PINKGREEN_API_KEY="$CX_API_KEY"
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
# Render to temp first so the backup check ignores the substituted plugin path.
RENDERED="$(mktemp)"
sed "s|__HINDSIGHT_PLUGIN_DIR__|${HOME}/.hindsight/coding-agents|g" "$TEMPLATE" >"$RENDERED"
# hindsight-coding-agents is optional: install-opencode-plugins.sh only
# presence-checks it and never installs it. Emitting its path unconditionally
# left a dangling entry in "plugins", which is a hard load error for opencode.
# Comment the entry out when the plugin is absent, leaving a valid empty array.
if [[ ! -f "$HOME/.hindsight/coding-agents/index.js" ]]; then
  sed -i "s|^\(\s*\)\"$HOME/\.hindsight/coding-agents\"\$|\1// hindsight-coding-agents not installed — enable with: bunx --yes @vectorize-io/hindsight-coding-agents@latest|" "$RENDERED"
  warn "hindsight plugin absent — omitted from opencode.jsonc plugins[]"
fi
if [[ -f "$TARGET" ]] && ! cmp -s "$RENDERED" "$TARGET"; then
  cp -f "$TARGET" "$TARGET.bak.$(date +%Y%m%d%H%M%S)"
  ok "existing config backed up"
fi
cp -f "$RENDERED" "$TARGET"
rm -f "$RENDERED"
chmod 600 "$TARGET"
ok "config → $TARGET (hindsight plugin path rendered)"

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

# ── V2 server plugins (firecrawl vendored port + hindsight) ──────────
if [[ -x "$KIT/scripts/install-opencode-plugins.sh" ]]; then
  bash "$KIT/scripts/install-opencode-plugins.sh" || warn "plugin setup had warnings (see above)"
else
  warn "install-opencode-plugins.sh missing — plugins not synced"
fi

# Clear any pre-existing bare service before the unit is (re)started.
stop_bare_service() {
  # `opencode serve --service` is a singleton: when another instance already
  # owns the service, a fresh one exits 0 straight away instead of serving.
  # That has two bad effects — the unit's Restart policy sees an immediate clean
  # exit, and the OLD instance keeps answering requests. If that old instance
  # was started without the Doppler vault (a bare `opencode serve`), every
  # {env:VAR} provider key resolves empty and inference fails with HTTP 401.
  #
  # The unit-managed service runs under `doppler run`, so it carries the vault
  # keys in its environment. Use that to tell the two apart, rather than
  # guessing from the process tree.
  local pid killed=0
  for pid in $(pgrep -f 'opencode serve --service' 2>/dev/null || true); do
    if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -q '^PINKGREEN_API_KEY='; then
      continue
    fi
    log "stopping pre-existing bare opencode service (pid $pid, no Doppler env)"
    kill "$pid" 2>/dev/null || true
    killed=$((killed + 1))
  done
  [[ "$killed" -gt 0 ]] && sleep 2
  return 0
}

# ── Persistent systemd service (survives reboot/restart) ──────────────────
# Root cause of recurring HTTP 401: the background server was once started
# under `doppler run` (keys in RAM) but systemd later restarted it bare —
# empty ~/.config/opencode/.env, no Doppler env — so {env:} resolved empty
# for every client while curl from a key-loaded shell still returned 200.
# Point the user unit at serve-opencode.sh (Doppler wrapper) so every
# (re)start carries the vault. No secret value is written to disk here,
# only the project/config names.
install_systemd_service() {
  have systemctl || { warn "systemctl missing — skipping persistent service"; return 0; }
  systemctl --user show-environment >/dev/null 2>&1 || { warn "no systemd user session — skipping persistent service"; return 0; }
  local unit_dir="$HOME/.config/systemd/user"
  local unit="$unit_dir/opencode.service"
  local dropin="$unit_dir/opencode.service.d/override.conf"
  mkdir -p "$unit_dir" "$unit_dir/opencode.service.d"
  # npx lives in nvm's node bin. MCP servers declared with an `npx` command
  # (e.g. agentation) fail to spawn — silently, with only an INFO line in the
  # journal — unless that directory is on the unit PATH. `firecrawl` survived
  # only because it launches through `bunx`, which is already in ~/.bun/bin.
  local node_bin=""
  node_bin="$(ls -d "$HOME"/.nvm/versions/node/v*/bin 2>/dev/null | sort -V | tail -1 || true)"
  local unit_path="$HOME/.opencode/bin:$HOME/.bun/bin:$HOME/.local/bin:$HOME/.local/share/vite-plus/bin"
  [[ -n "$node_bin" ]] && unit_path="$unit_path:$node_bin"
  unit_path="$unit_path:/usr/local/bin:/usr/bin:/bin"

  # UNIT_GEN is bumped whenever the unit body changes, so re-running this script
  # regenerates units written by an older template instead of leaving them stale.
  if [[ ! -f "$unit" ]] || grep -q "EnvironmentFile=%h/.config/opencode/.env" "$unit" 2>/dev/null \
    || ! grep -q "# UNIT_GEN=2" "$unit" 2>/dev/null; then
    cat >"$unit" <<EOF
# UNIT_GEN=2
[Unit]
Description=OpenCode (Doppler-backed)
After=network-online.target
[Service]
Environment="PATH=$unit_path"
ExecStart=$KIT/scripts/serve-opencode.sh --service
# on-failure, not always: \`opencode serve --service\` is a singleton and exits 0
# immediately when another instance already owns the service. With
# Restart=always that becomes a tight restart loop burning CPU.
Restart=on-failure
RestartSec=3
[Install]
WantedBy=default.target
EOF
    ok "systemd unit → $unit (via serve-opencode.sh)"
    [[ -n "$node_bin" ]] && ok "unit PATH includes nvm node bin → $node_bin"
  fi
  # Drop stale bare overrides (e.g. ExecStart=opencode serve --service without
  # doppler) that would silently reintroduce the empty-env 401.
  if [[ -f "$dropin" ]] && ! grep -q "serve-opencode.sh" "$dropin" 2>/dev/null; then
    rm -f "$dropin"
    ok "removed stale systemd override (bare opencode serve)"
  fi
  # A pre-existing bare service must go first, or the unit's singleton exits
  # instantly and the keyless instance keeps answering requests (HTTP 401).
  stop_bare_service
  if systemctl --user daemon-reload 2>/dev/null \
    && systemctl --user enable opencode.service >/dev/null 2>&1 \
    && systemctl --user restart opencode.service 2>/dev/null; then
    ok "systemd service restarted with Doppler env"
  else
    warn "could not (re)start systemd service — continuing with opencode service fallback"
    return 1
  fi
}

# ── Seed managed background service with keys ─────────────────────────
# `opencode serve --service` is auto-spawned by the first CLI/TUI call and
# inherits env from THAT parent. If it was spawned from a shell without
# Doppler env, {env:} placeholders resolve empty and every inference fails
# with HTTP 401 — while curl from a key-loaded shell still returns 200.
# Bounce it here under `doppler run` so the running service holds the keys.
# Preferred path is the persistent systemd unit (survives reboot); the
# `opencode service restart` below is a fallback for hosts without a systemd
# user session. No secret value is printed, logged, or written to disk here.
if install_systemd_service; then
  sleep 3
  if opencode api get /api/provider/cx 2>/dev/null | python3 -c '
import json, sys
key = json.load(sys.stdin)["data"]["settings"].get("apiKey", "")
assert key and "{env:" not in key, "key did not resolve"
print("provider cx key resolves in running service (%d chars)" % len(key))
'; then
    ok "provider keys resolve in running service"
  else
    warn "systemd restarted but cx key does not resolve — check: systemctl --user status opencode; bash $KIT/scripts/serve-opencode.sh --check"
  fi
elif have opencode && have doppler && [[ "$missing" == "0" ]]; then
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
