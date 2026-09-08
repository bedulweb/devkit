#!/usr/bin/env bash
# Install standard global agent skills.
# Only targets OpenCode + Claude Code (no 70-agent loop).
# skills CLI expects repeated -a flags, NOT comma-separated: -a opencode -a claude-code
set -uo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${PATH}"

# ensure node/npx on PATH (nvm lives in ~/.nvm, invisible to fresh shells)
[[ -f "${HOME}/.linux-devkit/env" ]] && source "${HOME}/.linux-devkit/env" 2>/dev/null || true
if ! command -v npx >/dev/null 2>&1; then
  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
fi

# Space or comma separated list → repeated -a flags
AGENTS_RAW="${DEVKIT_SKILL_AGENTS:-opencode claude-code}"
AGENTS_RAW="${AGENTS_RAW//,/ }"
MAX_RETRY="${DEVKIT_SKILL_RETRIES:-2}"
LOG="${DEVKIT_SKILL_LOG:-$HOME/.linux-devkit/skills-install.log}"
mkdir -p "$(dirname "$LOG")"

log()  { printf '%s\n' "$*" | tee -a "$LOG"; }
ok()   { log "  ✓ $*"; }
warn() { log "  ! $*"; }
fail() { log "  ✗ $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# source|skill_or_STAR|label|pin (pin = git SHA, appended as #sha; empty = latest)
# Pins are resolved HEADs — refresh with: git ls-remote <url> HEAD
# skills-manifest.txt mirrors this list (checked by tests/check-skills-manifest.sh).
SOURCES=(
  "emilkowalski/skills|STAR|emil-pack|d23d7f88a2e21c9e4b1418c7abe420f5c1052ba7"
  "mattpocock/skills|STAR|matt-pack|3cca18b368ae95cdbdebbff572ccafa662551015"
  "https://github.com/shadcn/ui|shadcn|shadcn|5c7072da672b0048bc6771e3204063a2537df91a"
  "shadcn/improve|STAR|shadcn-improve|03369ee6d7cafbfcecc4346539b05b3dc0a603bb"
  "https://github.com/jakubantalik/transitions-dev|transitions-dev|transitions-dev|038b0bdc75375c2beed51d1e824c98cdc7b86f8c"
  "pbakaus/impeccable|STAR|impeccable|2bc2879276c1f321a53c4ca99d3371e411329b52"
  "https://github.com/vercel-labs/agent-browser|agent-browser|agent-browser|471ab3852b47b98847f1d9c855c272bb62d0d50b"
  "https://github.com/jakubkrehel/skills|STAR|jakubkrehel-pack|267330e1adfc66a718fb65fa6918c1f06d0a689e"
  "https://github.com/jakubkrehel/make-interfaces-feel-better|make-interfaces-feel-better|feel-better|35545ea1512ad59fa463e6b1f95ca9c052981fe6"
)

add_one() {
  local source="$1" skill="$2" label="$3" ref="${4:-}"
  local attempt=1 rc=0
  local -a agent_flags=()
  local a
  for a in $AGENTS_RAW; do
    [[ -n "$a" ]] || continue
    agent_flags+=(-a "$a")
  done

  local pkg="$source"
  [[ -n "$ref" ]] && pkg="${source}#${ref}"
  local -a cmd=(npx --yes skills@latest add "$pkg" -g "${agent_flags[@]}" -y)

  if [[ "$skill" == "STAR" ]]; then
    cmd+=(--skill '*')
  else
    cmd+=(--skill "$skill")
  fi

  log ""
  log "==> [$label] ${cmd[*]}"

  while (( attempt <= MAX_RETRY )); do
    set +e
    "${cmd[@]}" >>"$LOG" 2>&1
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
      ok "$label OK (attempt $attempt)"
      return 0
    fi
    warn "$label attempt $attempt failed (exit $rc) — retry in 3s"
    # show last failure lines for monitoring
    tail -n 12 "$LOG" | sed 's/^/    | /' || true
    sleep 3
    attempt=$((attempt + 1))
  done
  fail "$label FAILED after $MAX_RETRY tries"
  return 0
}

: >"$LOG"
log "======== skills install $(date -u +%Y-%m-%dT%H:%M:%SZ) ========"
log "agents=$AGENTS_RAW"
log "before: $(ls -1 "${HOME}/.agents/skills" 2>/dev/null | wc -l) skills"

for entry in "${SOURCES[@]}"; do
  IFS='|' read -r src skill label ref <<<"$entry"
  add_one "$src" "$skill" "$label" "${ref:-}"
done

# aiforui.dev skills — token-gated. Token lives in Doppler, never in this repo.
# Override source: DEVKIT_AIFORUI_DOPPLER_PROJECT / DEVKIT_AIFORUI_DOPPLER_CONFIG
# Skip: DEVKIT_SKIP_AIFORUI=1
install_aiforui() {
  [[ "${DEVKIT_SKIP_AIFORUI:-0}" == "1" ]] && { warn "aiforui skipped (DEVKIT_SKIP_AIFORUI=1)"; return 0; }
  have npx || { warn "aiforui skipped (npx missing)"; return 0; }
  have doppler || { warn "aiforui skipped (doppler missing)"; return 0; }
  local project="${DEVKIT_AIFORUI_DOPPLER_PROJECT:-developer-workstation}"
  local config="${DEVKIT_AIFORUI_DOPPLER_CONFIG:-dev}"
  if ! doppler run --project="$project" --config="$config" -- \
      sh -c 'test -n "${AIFORUI_INSTALL_TOKEN:-}"' >/dev/null 2>&1; then
    warn "aiforui skipped (no AIFORUI_INSTALL_TOKEN in Doppler ${project}/${config})"
    return 0
  fi
  log ""
  log "==> [aiforui] token from Doppler ${project}/${config} (value never logged)"
  if doppler run --project="$project" --config="$config" -- \
      sh -c 'npx --yes @aiforui/install --token="$AIFORUI_INSTALL_TOKEN" --global -y' >>"$LOG" 2>&1; then
    ok "aiforui OK"
  else
    warn "aiforui install failed — see $LOG"
  fi
}

# local devkit skill
if [[ -f "${HOME}/linux-devkit/.agents/skills/devkit/SKILL.md" ]]; then
  mkdir -p "${HOME}/.agents/skills/devkit" \
           "${HOME}/.config/opencode/skills/devkit" \
           "${HOME}/.claude/skills/devkit"
  cp -f "${HOME}/linux-devkit/.agents/skills/devkit/SKILL.md" "${HOME}/.agents/skills/devkit/SKILL.md"
  cp -f "${HOME}/linux-devkit/.agents/skills/devkit/SKILL.md" "${HOME}/.config/opencode/skills/devkit/SKILL.md"
  cp -f "${HOME}/linux-devkit/.agents/skills/devkit/SKILL.md" "${HOME}/.claude/skills/devkit/SKILL.md"
  ok "devkit skill → global paths"
fi

install_aiforui

log "after: $(ls -1 "${HOME}/.agents/skills" 2>/dev/null | wc -l) skills"
log "======== done ========"
npx --yes skills@latest list -g 2>&1 | tee -a "$LOG" | tail -50
echo "Full log: $LOG"
