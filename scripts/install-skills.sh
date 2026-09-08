#!/usr/bin/env bash
# Install standard global agent skills.
# Only targets OpenCode + Claude Code (no 70-agent loop).
# skills CLI expects repeated -a flags, NOT comma-separated: -a opencode -a claude-code
set -uo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${PATH}"

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

# source|skill_or_STAR|label
SOURCES=(
  "emilkowalski/skills|STAR|emil-pack"
  "mattpocock/skills|STAR|matt-pack"
  "https://github.com/shadcn/ui|shadcn|shadcn"
  "shadcn/improve|STAR|shadcn-improve"
  "https://github.com/jakubantalik/transitions-dev|transitions-dev|transitions-dev"
  "pbakaus/impeccable|STAR|impeccable"
)

add_one() {
  local source="$1" skill="$2" label="$3"
  local attempt=1 rc=0
  local -a agent_flags=()
  local a
  for a in $AGENTS_RAW; do
    [[ -n "$a" ]] || continue
    agent_flags+=(-a "$a")
  done

  local -a cmd=(npx --yes skills@latest add "$source" -g "${agent_flags[@]}" -y)

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
  IFS='|' read -r src skill label <<<"$entry"
  add_one "$src" "$skill" "$label"
done

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

log "after: $(ls -1 "${HOME}/.agents/skills" 2>/dev/null | wc -l) skills"
log "======== done ========"
npx --yes skills@latest list -g 2>&1 | tee -a "$LOG" | tail -50
echo "Full log: $LOG"
