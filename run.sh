#!/usr/bin/env bash
# =============================================================================
# devkit run.sh — full setup until workspace is usable
#
# Fresh Ubuntu VM:
#   curl -fsSL https://raw.githubusercontent.com/ujang19/devkit/main/run.sh | bash
#
# Or local:
#   bash ~/linux-devkit/run.sh
#
# Optional env (export before running, or put in ~/.devkit.env):
#   GH_TOKEN                          GitHub PAT (private repos)
#   DOPPLER_TOKEN                     Doppler service token (dp.st.xxx)
#   DOPPLER_PROJECT                   project default (mis. wazapin-platform)
#   DOPPLER_CONFIG                    config default (dev|stg|prd)
#   DEVKIT_PROFILE                    minimal|default|full  (default: default)
#   DEVKIT_WITH_DOCKER                0|1  (default: 0)
#   DEVKIT_WITH_HERDR                 0|1  (default: 1 for default/full profile)
#   DEVKIT_SKIP_SKILLS                0|1  (default: 0)
#   DEVKIT_SKIP_INSTALL_DEPS          0|1  (default: 0)  # bun install per app
#   DEVKIT_KIT_REPO                   default: https://github.com/ujang19/devkit.git
# =============================================================================
set -euo pipefail

# ── colors ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; Z=$'\033[0m'
else
  B=; G=; Y=; R=; C=; Z=
fi
log()  { printf '%s==>%s %s\n' "${B}${C}" "$Z" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%s  !%s %s\n' "$Y" "$Z" "$*"; }
err()  { printf '%s  ✗%s %s\n' "$R" "$Z" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── load optional env file ──────────────────────────────────────────────────
for f in "${DEVKIT_ENV_FILE:-}" "$HOME/.devkit.env" "$HOME/linux-devkit/.devkit.env"; do
  [[ -n "${f:-}" && -f "$f" ]] || continue
  log "loading env from $f"
  set -a
  # shellcheck disable=SC1090
  source "$f"
  set +a
  break
done

KIT_REPO="${DEVKIT_KIT_REPO:-https://github.com/ujang19/devkit.git}"
PROFILE="${DEVKIT_PROFILE:-default}"
WITH_DOCKER="${DEVKIT_WITH_DOCKER:-0}"
# herdr on by default for default/full (user agent TUI stack)
WITH_HERDR="${DEVKIT_WITH_HERDR:-1}"
SKIP_SKILLS="${DEVKIT_SKIP_SKILLS:-0}"
SKIP_DEPS="${DEVKIT_SKIP_INSTALL_DEPS:-0}"
DOPPLER_CONFIG="${DOPPLER_CONFIG:-dev}"
DOPPLER_API_HOST="${DOPPLER_API_HOST:-https://api.doppler.com}"

export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${HOME}/.opencode/bin:${HOME}/.local/go/bin:${HOME}/go/bin:${PATH}"
export GOPATH="${GOPATH:-$HOME/go}"

# ── helpers ─────────────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }

ensure_git() {
  if ! have git; then
    if have sudo && sudo -n true 2>/dev/null; then
      sudo apt-get update -y && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates
    else
      die "git/curl required. Install: sudo apt-get install -y git curl"
    fi
  fi
  have curl || die "curl required"
}

# ── step 1: get kit ─────────────────────────────────────────────────────────
step_kit() {
  log "1/7  fetch devkit repo"
  if [[ -f "$HOME/linux-devkit/install.sh" ]]; then
    if [[ -d "$HOME/linux-devkit/.git" ]]; then
      git -C "$HOME/linux-devkit" pull --ff-only 2>/dev/null || warn "pull skipped (local changes?)"
    fi
    ok "kit present: $HOME/linux-devkit"
  else
    git clone --depth 1 "$KIT_REPO" "$HOME/linux-devkit"
    ok "cloned $KIT_REPO → ~/linux-devkit"
  fi
  # keep name stable: linux-devkit (even if repo is ujang19/devkit)
  ln -sfn "$HOME/linux-devkit" "$HOME/devkit" 2>/dev/null || true
}

# ── step 2: install tools ───────────────────────────────────────────────────
step_install() {
  log "2/7  install tools (profile=$PROFILE docker=$WITH_DOCKER herdr=$WITH_HERDR)"
  local flags=(--profile "$PROFILE" -y)
  [[ "$WITH_DOCKER" == "1" ]] && flags+=(--with-docker)
  if [[ "$WITH_HERDR" == "1" ]]; then
    flags+=(--with-herdr)
  else
    flags+=(--no-herdr)
  fi
  DEVKIT_WITH_HERDR="$WITH_HERDR" bash "$HOME/linux-devkit/install.sh" "${flags[@]}"
  export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${HOME}/.opencode/bin:${HOME}/.local/go/bin:${PATH}"
  # shellcheck disable=SC1090
  [[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc" 2>/dev/null || true
  export PATH="${HOME}/.local/bin:${HOME}/.bun/bin:${HOME}/.opencode/bin:${HOME}/.local/go/bin:${HOME}/go/bin:${PATH}"
  have devkit || die "devkit CLI missing after install"
  if [[ "$WITH_HERDR" == "1" ]]; then
    have herdr && ok "herdr $(herdr --version 2>/dev/null | head -1)" || warn "herdr missing after install"
  fi
  ok "tools installed"
}

# ── step 3: GitHub auth for private repos ───────────────────────────────────
step_github() {
  log "3/7  GitHub access (private repos)"

  if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    export GH_TOKEN="${GH_TOKEN:-$GITHUB_TOKEN}"
    export GITHUB_TOKEN="${GITHUB_TOKEN:-$GH_TOKEN}"
    # Prefer env token for gh + git
    if have gh; then
      echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null \
        || warn "gh auth login --with-token failed (token may still work for API)"
      # ensure git uses gh helper
      gh auth setup-git 2>/dev/null || true
    fi
    # HTTPS clone fallback with token (if gh helper missing)
    git config --global url."https://x-access-token:${GH_TOKEN}@github.com/".insteadOf "https://github.com/" 2>/dev/null || true
    ok "using GH_TOKEN / GITHUB_TOKEN from environment"
    if have gh; then
      local user
      user="$(gh api user --jq .login 2>/dev/null || true)"
      [[ -n "$user" ]] && ok "GitHub user: $user"
    fi
    return 0
  fi

  if have gh && gh auth status >/dev/null 2>&1; then
    ok "gh already logged in"
    gh auth setup-git 2>/dev/null || true
    return 0
  fi

  warn "No GH_TOKEN and gh not logged in."
  warn "Public repos will restore; private (wabase/wazapin) need:"
  warn "  export GH_TOKEN=github_pat_xxx"
  warn "  # then re-run: bash ~/linux-devkit/run.sh"
}

# ── step 4: Doppler (secrets) ───────────────────────────────────────────────
step_doppler() {
  log "4/7  Doppler (secrets)"

  if ! have doppler; then
    warn "doppler CLI missing — skip (bash ~/linux-devkit/install.sh)"
    return 0
  fi

  local tok="${DOPPLER_TOKEN:-}"
  if [[ -z "$tok" ]]; then
    warn "DOPPLER_TOKEN not set — skip (isi di ~/.devkit.env)"
    warn "  DOPPLER_TOKEN=dp.st.xxx"
    warn "  DOPPLER_PROJECT=wazapin-platform"
    warn "  DOPPLER_CONFIG=dev"
    return 0
  fi

  export DOPPLER_TOKEN
  if doppler whoami >/dev/null 2>&1; then
    ok "Doppler authenticated"
    doppler whoami 2>/dev/null | head -12 || true
  else
    doppler configure set token "$tok" 2>/dev/null || true
    if doppler whoami >/dev/null 2>&1; then
      ok "Doppler authenticated (token dikonfigurasi)"
      doppler whoami 2>/dev/null | head -12 || true
    else
      warn "Doppler auth gagal — cek DOPPLER_TOKEN di ~/.devkit.env"
    fi
  fi
}

# ── step 5: restore projects ────────────────────────────────────────────────
step_restore() {
  log "5/7  restore projects from projects.yaml"
  mkdir -p "$HOME/projects/apps"
  # ensure registry available to devkit
  if [[ -f "$HOME/linux-devkit/projects.yaml" ]]; then
    mkdir -p "$HOME/.linux-devkit"
    cp -f "$HOME/linux-devkit/projects.yaml" "$HOME/.linux-devkit/projects.yaml"
  fi
  devkit restore
  ok "restore finished"
  devkit list || true
}

# ── step 6: agent skills ────────────────────────────────────────────────────
step_skills() {
  log "6/7  agent skills pack"
  if [[ "$SKIP_SKILLS" == "1" ]]; then
    warn "skipped (DEVKIT_SKIP_SKILLS=1)"
    return 0
  fi
  if [[ -x "$HOME/linux-devkit/scripts/install-skills.sh" ]]; then
    bash "$HOME/linux-devkit/scripts/install-skills.sh" || warn "skills install had errors"
  else
    warn "install-skills.sh missing"
  fi
  # ensure our devkit skill is present globally
  if [[ -f "$HOME/linux-devkit/.agents/skills/devkit/SKILL.md" ]]; then
    mkdir -p "$HOME/.agents/skills/devkit" "$HOME/.config/opencode/skills/devkit" "$HOME/.claude/skills/devkit"
    cp -f "$HOME/linux-devkit/.agents/skills/devkit/SKILL.md" "$HOME/.agents/skills/devkit/SKILL.md"
    cp -f "$HOME/linux-devkit/.agents/skills/devkit/SKILL.md" "$HOME/.config/opencode/skills/devkit/SKILL.md"
    cp -f "$HOME/linux-devkit/.agents/skills/devkit/SKILL.md" "$HOME/.claude/skills/devkit/SKILL.md"
    ok "devkit skill installed globally"
  fi
  if have grok && [[ -x "$HOME/linux-devkit/scripts/restore-grok.sh" ]]; then
    "$HOME/linux-devkit/scripts/restore-grok.sh" || warn "Grok restore had errors"
  fi
}

# ── step 7: install app deps (bun/npm) ──────────────────────────────────────
step_deps() {
  log "7/7  install project dependencies"
  if [[ "$SKIP_DEPS" == "1" ]]; then
    warn "skipped (DEVKIT_SKIP_INSTALL_DEPS=1)"
    return 0
  fi
  have bun || { warn "bun missing — skip deps"; return 0; }

  local key path
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    path="$(devkit path "$key" 2>/dev/null || true)"
    [[ -n "$path" && -d "$path" ]] || continue
    if [[ -f "$path/package.json" ]]; then
      log "  bun install @ $key ($path)"
      (cd "$path" && bun install) || warn "bun install failed: $key"
    elif [[ -f "$path/go.mod" ]]; then
      log "  go mod download @ $key"
      (cd "$path" && go mod download) || warn "go mod failed: $key"
    else
      ok "no package.json/go.mod: $key (skip)"
    fi
  done < <(devkit list 2>/dev/null | sed -n 's/^  • \([^ ]*\).*/\1/p' || true)
}

# ── verify ──────────────────────────────────────────────────────────────────
step_verify() {
  log "verify"
  devkit doctor || true
  echo ""
  local key path okc=0 failc=0
  for key in wabase-core wazapin-platform wazapin-web betterpay; do
    path="$(devkit path "$key" 2>/dev/null || true)"
    if [[ -d "${path}/.git" ]]; then
      ok "$key → $path"
      okc=$((okc + 1))
    else
      warn "$key missing (private? set GH_TOKEN and re-run restore)"
      failc=$((failc + 1))
    fi
  done
  echo ""
  printf '%sReady.%s  projects ok=%s missing=%s\n' "$G" "$Z" "$okc" "$failc"
}

print_usage_guide() {
  cat <<EOF

${B}${G}═══════════════════════════════════════════════════════════${Z}
${B}  devkit setup complete — how to use${Z}
${B}${G}═══════════════════════════════════════════════════════════${Z}

${B}Paths${Z}
  wabase-core       \$(devkit path wabase-core)
  wazapin-platform  \$(devkit path wazapin-platform)
  wazapin-web       \$(devkit path wazapin-web)
  betterpay         \$(devkit path betterpay)

${B}Everyday${Z}
  source ~/.bashrc
  devkit list
  cd "\$(devkit path wabase-core)"

${B}With Doppler secrets${Z}
  cd "\$(devkit path wabase-core)"
  doppler run --project=wabase-core --config=${DOPPLER_CONFIG:-dev} -- bun run dev
  # Cloudflare:
  doppler run --project=wabase-core --config=${DOPPLER_CONFIG:-dev} -- bunx wrangler deploy

${B}PM2 (after you have a start script)${Z}
  cd "\$(devkit path wabase-core)"
  doppler run --project=wabase-core --config=prod -- pm2 start ecosystem.config.cjs
  # or: pm2 start bun --name wabase-core -- run start

${B}Agents (OpenCode / others)${Z}
  opencode
  # skill "devkit" is global — ask to add/restore projects

${B}Re-run this script anytime (idempotent)${Z}
  bash ~/linux-devkit/run.sh

${B}Env file (optional)${Z}
  cp ~/linux-devkit/.devkit.env.example ~/.devkit.env
  # edit secrets, then: bash ~/linux-devkit/run.sh

${B}If private clone failed${Z}
  export GH_TOKEN=github_pat_xxx
  devkit restore

EOF
}

# ── main ────────────────────────────────────────────────────────────────────
main() {
  echo ""
  log "devkit full setup  (repo=$KIT_REPO profile=$PROFILE)"
  echo ""

  ensure_git
  step_kit
  step_install
  step_github
  step_doppler
  step_restore
  step_skills
  step_deps
  step_verify
  print_usage_guide
}

main "$@"
