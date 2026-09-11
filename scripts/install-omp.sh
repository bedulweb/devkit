#!/usr/bin/env bash
# install-omp.sh — Install OMP + models + MCP + Daytona CLI + E2B
# Mirrors install-codex.sh: loads secrets from Doppler, writes config, installs everything.
# Called by install.sh install_omp() or standalone.
set -euo pipefail

OMP_HOME="${OMP_HOME:-$HOME/.omp}"
OMP_AGENT="$OMP_HOME/agent"
DOPPLER_PROJECT="${DEVKIT_CODEX_DOPPLER_PROJECT:-developer-workstation}"
DOPPLER_CONFIG="${DEVKIT_CODEX_DOPPLER_CONFIG:-dev}"
LOCAL_BIN="${HOME}/.local/bin"
PINKGREEN_URL="${PINKGREEN_BASE_URL:-https://ai.sabergaming.my.id/v1}"
ROUTEID_URL="${ROUTEID_BASE_URL:-https://routeid.trainerhub.workers.dev/v1}"

log()  { printf '\033[1;36m==> omp:\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ── Load secrets from Doppler ─────────────────────────────────────────
load_secret() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then return 0; fi
  if command -v doppler >/dev/null 2>&1 && doppler secrets get "$name" \
      --project="$DOPPLER_PROJECT" --config="$DOPPLER_CONFIG" --plain >/tmp/omp-secret 2>/dev/null; then
    export "$name=$(tr -d '\r\n' </tmp/omp-secret)"
  fi
}

log "loading secrets from Doppler"
load_secret PINKGREEN_API_KEY
load_secret EXA_API_KEY
load_secret FIRECRAWL_API_KEY
load_secret E2B_API_KEY
load_secret DAYTONA_API_KEY
load_secret GITHUB_TOKEN
load_secret FIGMA_API_KEY
if [[ -z "${OPENAI_API_KEY:-}" && -n "${PINKGREEN_API_KEY:-}" ]]; then
  export OPENAI_API_KEY="$PINKGREEN_API_KEY"
fi

# ── Install OMP binary ───────────────────────────────────────────────
install_omp_binary() {
  if have omp; then ok "omp $(omp --version 2>/dev/null | head -1)"; return; fi
  log "installing OMP (pi-coding-agent)"
  if have bun; then
    bun install -g @oh-my-pi/pi-coding-agent || die "omp install failed"
  elif have npm; then
    npm install -g @oh-my-pi/pi-coding-agent || die "omp install failed"
  else
    die "need bun or npm to install OMP"
  fi
  # ensure omp is on PATH
  if ! have omp && [[ -x "$HOME/.bun/bin/omp" ]]; then
    ln -sf "$HOME/.bun/bin/omp" "$LOCAL_BIN/omp" 2>/dev/null || true
  fi
  ok "omp $(omp --version 2>/dev/null | head -1 || echo installed)"
}

# ── Write models.yml ─────────────────────────────────────────────────
write_models() {
  log "writing models.yml"
  mkdir -p "$OMP_AGENT"
  local pinkgreen_key="${PINKGREEN_API_KEY:-sk-f170562316110c76-jneosk-ae223cf0}"
  local routeid_key="${ROUTEID_API_KEY:-Mastah123}"
  cat > "$OMP_AGENT/models.yml" <<EOF
providers:
  routeid:
    baseUrl: ${ROUTEID_URL}
    api: openai-completions
    apiKey: ${routeid_key}
    models:
      - id: glm-5.2
        name: RouteID GLM-5.2
        reasoning: true
        contextWindow: 1048576
        maxTokens: 131072
      - id: deepseek-v4-pro-0813
        name: RouteID DeepSeek V4 Pro 0813
        reasoning: true
        contextWindow: 1048576
        maxTokens: 393216
      - id: deepseek-v4-flash-0731
        name: RouteID DeepSeek V4 Flash 0731
        reasoning: true
        contextWindow: 1048576
        maxTokens: 393216
      - id: kimi-k3
        name: RouteID Kimi K3
        reasoning: true
        contextWindow: 1048576
        maxTokens: 1048576
      - id: qwen3.8-max
        name: RouteID Qwen3.8 Max
        reasoning: true
        contextWindow: 1048576
        maxTokens: 131072
      - id: qwen3.8-flash
        name: RouteID Qwen3.8 Flash
        reasoning: true
        contextWindow: 1048576
        maxTokens: 131072
  pinkgreen:
    baseUrl: ${PINKGREEN_URL}
    api: openai-completions
    apiKey: ${pinkgreen_key}
    models:
      - id: cx/gpt-6-astra
        name: GPT-6 Astra
        contextWindow: 1050000
        maxTokens: 128000
      - id: cx/gpt-5.6-sol
        name: GPT-5.6 Sol
        contextWindow: 1050000
        maxTokens: 128000
      - id: cx/gpt-5.6-terra
        name: GPT-5.6 Terra
        contextWindow: 272000
        maxTokens: 128000
      - id: cx/gpt-5.6-luna
        name: GPT-5.6 Luna
        contextWindow: 272000
        maxTokens: 128000
EOF
  chmod 600 "$OMP_AGENT/models.yml"
  ok "models.yml → $OMP_AGENT/models.yml"
}

# ── Write config.yml ─────────────────────────────────────────────────
write_config() {
  log "writing config.yml"
  cat > "$OMP_AGENT/config.yml" <<'EOF'
modelRoles:
  default: routeid/glm-5.2
  slow: pinkgreen/cx/gpt-5.6-sol
  smol: routeid/deepseek-v4-flash-0731:high
setupVersion: 2
symbolPreset: nerd
display:
  shimmer: classic
hideThinkingBlock: true
memory:
  backend: hindsight
error:
  notify: "on"
autolearn:
  enabled: true
  autoContinue: true
disabledProviders:
  - openai
memories:
  enabled: true
EOF
  chmod 600 "$OMP_AGENT/config.yml"
  ok "config.yml → $OMP_AGENT/config.yml"
}

# ── Write mcp.json ───────────────────────────────────────────────────
write_mcp() {
  log "writing mcp.json"
  local exa_key="${EXA_API_KEY:-}"
  local firecrawl_key="${FIRECRAWL_API_KEY:-fc-29c6017f144f45199a891f80f7df1aa8}"
  local e2b_key="${E2B_API_KEY:-}"
  local gh_token="${GITHUB_TOKEN:-}"
  local bunx_path="${HOME}/.bun/bin/bunx"

  # If GITHUB_TOKEN not set, try gh auth token
  if [[ -z "$gh_token" ]] && have gh; then
    gh_token="$(gh auth token 2>/dev/null || true)"
  fi

  # If EXA_API_KEY not set, warn
  [[ -z "$exa_key" ]] && warn "EXA_API_KEY not found — exa MCP will need manual setup"

  cat > "$OMP_AGENT/mcp.json" <<EOF
{
  "\$schema": "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json",
  "mcpServers": {
    "firecrawl": {
      "type": "stdio",
      "enabled": true,
      "command": "${bunx_path}",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "${firecrawl_key}"
      }
    },
    "exa": {
      "type": "http",
      "enabled": true,
      "url": "https://mcp.exa.ai/mcp?tools=web_search_exa%2Cweb_fetch_exa",
      "headers": {
        "x-api-key": "${exa_key}"
      }
    }
EOF

  # GitHub MCP (only if we have a token)
  if [[ -n "$gh_token" ]]; then
    cat >> "$OMP_AGENT/mcp.json" <<EOF
    ,
    "github": {
      "type": "http",
      "enabled": true,
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${gh_token}"
      }
    }
EOF
  fi

  # Linear MCP (OAuth — user must /mcp reauth after install)
  cat >> "$OMP_AGENT/mcp.json" <<EOF
    ,
    "linear": {
      "type": "http",
      "enabled": true,
      "url": "https://mcp.linear.app/mcp"
    }
EOF

  # E2B MCP (only if we have a key)
  if [[ -n "$e2b_key" ]]; then
    cat >> "$OMP_AGENT/mcp.json" <<EOF
    ,
    "e2b-server": {
      "type": "stdio",
      "enabled": true,
      "command": "npx",
      "args": ["-y", "@e2b/mcp-server"],
      "env": {
        "E2B_API_KEY": "${e2b_key}"
      }
    }
EOF
  fi

  # Daytona MCP (only if daytona binary is installed)
  if have daytona; then
    cat >> "$OMP_AGENT/mcp.json" <<EOF
    ,
    "daytona": {
      "type": "stdio",
      "enabled": true,
      "command": "daytona",
      "args": ["mcp", "start"],
      "env": {
        "HOME": "${HOME}",
        "PATH": "${HOME}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      }
    }
EOF
  fi

  cat >> "$OMP_AGENT/mcp.json" <<EOF
  }
}
EOF
  chmod 600 "$OMP_AGENT/mcp.json"
  ok "mcp.json → $OMP_AGENT/mcp.json"
}

# ── Install Daytona CLI ──────────────────────────────────────────────
install_daytona() {
  local daytona_key="${DAYTONA_API_KEY:-}"
  if have daytona && [[ -z "$daytona_key" ]]; then
    ok "daytona $(daytona --version 2>/dev/null | head -1)"
    return
  fi
  log "installing Daytona CLI via Homebrew"
  # Check if brew exists
  local brew_bin=""
  if have brew; then
    brew_bin="brew"
  elif [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
  else
    warn "Homebrew not found — installing Daytona binary directly"
    # Fallback: direct binary download
    local arch="amd64"
    [[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]] && arch="arm64"
    curl -fL "https://github.com/daytonaio/daytona/releases/latest/download/daytona-linux-${arch}" \
      -o /tmp/daytona 2>/dev/null || { warn "Daytona download failed"; return 0; }
    mv /tmp/daytona /usr/local/bin/daytona 2>/dev/null || cp /tmp/daytona "$LOCAL_BIN/daytona"
    chmod +x "$(command -v daytona)" 2>/dev/null || true
  fi
  if [[ -n "$brew_bin" ]]; then
    # Install as linuxbrew user if running as root
    if [[ "$(id -u)" -eq 0 && -d /home/linuxbrew ]]; then
      su - linuxbrew -c "eval \"\$($brew_bin shellenv bash)\" && brew install daytonaio/cli/daytona" 2>/dev/null || warn "brew install daytona failed"
      # Copy to system PATH
      local daytona_cellar
      daytona_cellar="$(find /home/linuxbrew/.linuxbrew/Cellar/daytona -name daytona -type f 2>/dev/null | head -1)"
      [[ -n "$daytona_cellar" ]] && cp "$daytona_cellar" /usr/local/bin/daytona && chmod +x /usr/local/bin/daytona
    else
      eval "$($brew_bin shellenv bash)" && brew install daytonaio/cli/daytona 2>/dev/null || warn "brew install daytona failed"
    fi
  fi
  if have daytona; then
    if [[ -n "$daytona_key" ]]; then
      daytona login --api-key "$daytona_key" 2>/dev/null || true
    fi
    ok "daytona $(daytona --version 2>/dev/null | head -1)"
  else
    warn "daytona CLI not installed — MCP config will skip it"
  fi
}

# ── Write .env ────────────────────────────────────────────────────────
write_env() {
  log "writing .env"
  local exa_key="${EXA_API_KEY:-}"
  cat > "$OMP_AGENT/.env" <<EOF
EXA_API_KEY=${exa_key}
EOF
  chmod 600 "$OMP_AGENT/.env"
  ok ".env → $OMP_AGENT/.env"
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
  log "OMP installer starting"
  mkdir -p "$OMP_AGENT"

  install_omp_binary
  write_models
  write_config
  install_daytona
  write_mcp
  write_env

  echo
  log "done — OMP ready"
  echo
  cat <<EOF
Next steps:
  1. Open a new shell (or: source ~/.bashrc)
  2. Run:  omp
  3. In OMP TUI, type:  /mcp reload
  4. For Linear OAuth:   /mcp reauth linear
  5. For GitHub (if no token): /mcp reauth github

Config files:
  ~/.omp/agent/config.yml    — model roles + settings
  ~/.omp/agent/models.yml   — RouteID + PinkGreen providers
  ~/.omp/agent/mcp.json     — MCP servers (firecrawl, exa, github, linear, e2b, daytona)
  ~/.omp/agent/.env         — env vars for MCP

Re-run anytime (idempotent):
  bash ~/linux-devkit/scripts/install-omp.sh
EOF
}

main "$@"
