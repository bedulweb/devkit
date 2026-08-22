#!/usr/bin/env bash
# linux-devkit — one-shot installer for a fresh Ubuntu/Debian VM
#
# Design goals:
#   - No heavy package manager deps beyond curl + bash + (optional) sudo
#   - Most tools install to ~/.local (no root required when possible)
#   - Idempotent: safe to re-run
#   - Offline-friendly after first cache: downloads go to ~/.cache/linux-devkit
#
# Usage:
#   curl -fsSL https://.../install.sh | bash
#   # or from this repo:
#   bash install.sh
#   bash install.sh --with-docker --with-flutter --profile full
#
set -euo pipefail

DEVKIT_VERSION="1.0.0"
DEVKIT_HOME="${DEVKIT_HOME:-$HOME/.linux-devkit}"
CACHE_DIR="${DEVKIT_CACHE:-$HOME/.cache/linux-devkit}"
LOCAL_BIN="${HOME}/.local/bin"
PROFILE="default"          # minimal | default | full
WITH_DOCKER=0
WITH_FLUTTER=0
WITH_ANDROID=0
WITH_HERDR=0
WITH_GROK=0
WITH_CCGRAM=0
WITH_DOPPLER=1
NONINTERACTIVE=1
ASSUME_YES=0
SKIP_APT=0
DEVKIT_GIT_USER_NAME="${DEVKIT_GIT_USER_NAME:-bedulweb}"
DEVKIT_GIT_USER_EMAIL="${DEVKIT_GIT_USER_EMAIL:-ujangas1908@gmail.com}"

# ── colors ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_GREEN=; C_YELLOW=; C_RED=; C_CYAN=
fi

log()  { printf '%s==>%s %s\n' "$C_BOLD$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── args ──────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
linux-devkit installer v${DEVKIT_VERSION}

Usage: bash install.sh [options]

Profiles:
  --profile minimal   git, curl, gh, jq, rg, fd, fzf, uv, nvm+node
  --profile default   minimal + herdr + direnv + starship + doppler (+ docker if --with-docker)
  --profile full      default + flutter + grok + ccgram hooks

Optional components:
  --with-docker       Install Docker Engine (needs sudo)
  --with-flutter      Install Flutter SDK to ~/flutter
  --with-android      Android cmdline-tools only (needs Java)
  --with-herdr        Install herdr TUI (on by default for default/full)
  --no-herdr          Skip herdr
  --with-grok         Ensure grok/agent path hints (does not download proprietary bin)
  --with-ccgram       Install ccgram (uv tool)
  --no-doppler        Skip Doppler CLI
  --skip-apt          Never call apt (user-space only)
  -y, --yes           Non-interactive (default)

Examples:
  bash install.sh --profile default --with-docker -y
  bash install.sh --profile full --with-docker --with-flutter -y
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --with-docker) WITH_DOCKER=1; shift ;;
    --with-flutter) WITH_FLUTTER=1; shift ;;
    --with-android) WITH_ANDROID=1; shift ;;
    --with-herdr) WITH_HERDR=1; shift ;;
    --no-herdr) WITH_HERDR=0; shift ;;
    --with-grok) WITH_GROK=1; shift ;;
    --with-ccgram) WITH_CCGRAM=1; shift ;;
    --no-doppler) WITH_DOPPLER=0; shift ;;
    --skip-apt) SKIP_APT=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

case "$PROFILE" in
  minimal|default|full) ;;
  *) die "Invalid --profile: $PROFILE (minimal|default|full)" ;;
esac

# default + full always get herdr (agent TUI stack); minimal stays lean
if [[ "$PROFILE" == "default" || "$PROFILE" == "full" ]]; then
  WITH_HERDR=1
fi

if [[ "$PROFILE" == "full" ]]; then
  WITH_DOCKER=1
  WITH_FLUTTER=1
  WITH_HERDR=1
  WITH_CCGRAM=1
fi

# env override (run.sh / .devkit.env)
if [[ "${DEVKIT_WITH_HERDR:-}" == "1" ]]; then WITH_HERDR=1; fi
if [[ "${DEVKIT_WITH_HERDR:-}" == "0" ]]; then WITH_HERDR=0; fi

# ── helpers ───────────────────────────────────────────────────────────
ensure_dirs() {
  mkdir -p "$LOCAL_BIN" "$CACHE_DIR" "$DEVKIT_HOME" \
    "$HOME/.config" "$HOME/.local/share/man/man1"
}

configure_git_identity() {
  git config --global user.name "$DEVKIT_GIT_USER_NAME"
  git config --global user.email "$DEVKIT_GIT_USER_EMAIL"
  ok "Git identity → ${DEVKIT_GIT_USER_NAME} <${DEVKIT_GIT_USER_EMAIL}>"
}

ensure_path_snippet() {
  local rc="$HOME/.bashrc"
  local marker="# >>> linux-devkit >>>"
  local block
  block=$(cat <<'EOF'
# >>> linux-devkit >>>
export PATH="$HOME/.local/bin:$PATH"
# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
# bun
[ -s "$HOME/.bun/bin/bun" ] && export PATH="$HOME/.bun/bin:$PATH"
# flutter
[ -d "$HOME/flutter/bin" ] && export PATH="$HOME/flutter/bin:$PATH"
# android
[ -d "$HOME/Android/Sdk" ] && export ANDROID_HOME="$HOME/Android/Sdk" && export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
# grok
[ -d "$HOME/.grok/bin" ] && export PATH="$HOME/.grok/bin:$PATH"
# go
export GOPATH="${GOPATH:-$HOME/go}"
[ -d "$HOME/.local/go/bin" ] && export PATH="$HOME/.local/go/bin:$GOPATH/bin:$PATH"
# opencode
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"
# cargo
[ -s "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
# direnv
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"
# starship
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
# <<< linux-devkit <<<
EOF
)
  touch "$rc"
  if ! grep -qF "$marker" "$rc" 2>/dev/null; then
    printf '\n%s\n' "$block" >> "$rc"
    ok "PATH snippet appended to ~/.bashrc"
  else
    ok "PATH snippet already in ~/.bashrc"
  fi
  # shellcheck disable=SC1090
  export PATH="$HOME/.local/bin:$PATH"
}

need_cmd() {
  have "$1" || die "Missing required command: $1"
}

download() {
  # download URL DEST
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    ok "cached $(basename "$dest")"
    return 0
  fi
  log "download $(basename "$dest")"
  curl -fsSL --retry 3 --retry-delay 1 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
}

github_latest_tag() {
  # owner/repo → tag without leading v
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2>/dev/null \
    || true
}

arch_go() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "Unsupported arch: $(uname -m)" ;;
  esac
}

can_sudo() {
  have sudo && sudo -n true 2>/dev/null
}

# ── apt base (optional, only if sudo available) ───────────────────────
install_apt_base() {
  [[ "$SKIP_APT" == "1" ]] && { warn "skip apt (--skip-apt)"; return 0; }
  if ! can_sudo; then
    warn "no passwordless sudo — skipping apt packages (user-space install only)"
    return 0
  fi
  log "apt base packages"
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl wget git unzip zip tar xz-utils \
    build-essential pkg-config \
    python3 python3-pip python3-venv python3-yaml \
    jq tree tmux htop openssh-client \
    software-properties-common gnupg lsb-release \
    libssl-dev zlib1g-dev || warn "some apt packages failed"
  ok "apt base done"
}

# ── user-space tools (no root) ────────────────────────────────────────
install_gh() {
  if have gh; then ok "gh $(gh --version | head -1)"; return; fi
  log "install gh (GitHub CLI)"
  local ver arch tgz dir
  ver="$(github_latest_tag cli/cli)"
  [[ -n "$ver" ]] || ver="2.96.0"
  arch="$(arch_go)"
  tgz="$CACHE_DIR/gh_${ver}_linux_${arch}.tar.gz"
  download "https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_${arch}.tar.gz" "$tgz"
  dir="$CACHE_DIR/gh_${ver}_linux_${arch}"
  rm -rf "$dir"
  tar -C "$CACHE_DIR" -xzf "$tgz"
  install -m 755 "$dir/bin/gh" "$LOCAL_BIN/gh"
  ok "gh $($LOCAL_BIN/gh --version | head -1)"
}

install_jq() {
  if have jq; then ok "jq $(jq --version)"; return; fi
  log "install jq"
  local arch ver="1.7.1" bin
  case "$(uname -m)" in
    x86_64|amd64) bin="jq-linux-amd64" ;;
    aarch64|arm64) bin="jq-linux-arm64" ;;
    *) die "no jq binary for $(uname -m)" ;;
  esac
  download "https://github.com/jqlang/jq/releases/download/jq-${ver}/${bin}" "$CACHE_DIR/${bin}"
  install -m 755 "$CACHE_DIR/${bin}" "$LOCAL_BIN/jq"
  ok "jq $($LOCAL_BIN/jq --version)"
}

install_rg() {
  if have rg; then ok "rg $(rg --version | head -1)"; return; fi
  log "install ripgrep"
  local ver arch tgz dir
  ver="$(github_latest_tag BurntSushi/ripgrep)"
  [[ -n "$ver" ]] || ver="14.1.1"
  case "$(uname -m)" in
    x86_64|amd64) arch="x86_64-unknown-linux-musl" ;;
    aarch64|arm64) arch="aarch64-unknown-linux-gnu" ;;
    *) die "no rg for $(uname -m)" ;;
  esac
  tgz="$CACHE_DIR/ripgrep-${ver}-${arch}.tar.gz"
  download "https://github.com/BurntSushi/ripgrep/releases/download/${ver}/ripgrep-${ver}-${arch}.tar.gz" "$tgz"
  dir="$CACHE_DIR/ripgrep-${ver}-${arch}"
  rm -rf "$dir"
  tar -C "$CACHE_DIR" -xzf "$tgz"
  install -m 755 "$dir/rg" "$LOCAL_BIN/rg"
  ok "rg $($LOCAL_BIN/rg --version | head -1)"
}

install_fd() {
  if have fd || have fdfind; then ok "fd present"; return; fi
  log "install fd"
  local ver arch tgz dir
  ver="$(github_latest_tag sharkdp/fd)"
  [[ -n "$ver" ]] || ver="10.2.0"
  case "$(uname -m)" in
    x86_64|amd64) arch="x86_64-unknown-linux-musl" ;;
    aarch64|arm64) arch="aarch64-unknown-linux-gnu" ;;
    *) die "no fd for $(uname -m)" ;;
  esac
  tgz="$CACHE_DIR/fd-v${ver}-${arch}.tar.gz"
  download "https://github.com/sharkdp/fd/releases/download/v${ver}/fd-v${ver}-${arch}.tar.gz" "$tgz"
  dir="$CACHE_DIR/fd-v${ver}-${arch}"
  rm -rf "$dir"
  tar -C "$CACHE_DIR" -xzf "$tgz"
  install -m 755 "$dir/fd" "$LOCAL_BIN/fd"
  ok "fd $($LOCAL_BIN/fd --version)"
}

install_fzf() {
  if have fzf; then ok "fzf $(fzf --version)"; return; fi
  log "install fzf"
  local ver tgz dir arch
  ver="$(github_latest_tag junegunn/fzf)"
  [[ -n "$ver" ]] || ver="0.60.3"
  case "$(uname -m)" in
    x86_64|amd64) arch="linux_amd64" ;;
    aarch64|arm64) arch="linux_arm64" ;;
    *) die "no fzf for $(uname -m)" ;;
  esac
  tgz="$CACHE_DIR/fzf-${ver}-${arch}.tar.gz"
  download "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf-${ver}-${arch}.tar.gz" "$tgz"
  tar -C "$CACHE_DIR" -xzf "$tgz"
  install -m 755 "$CACHE_DIR/fzf" "$LOCAL_BIN/fzf"
  ok "fzf $($LOCAL_BIN/fzf --version)"
}

install_uv() {
  if have uv; then ok "uv $(uv --version)"; return; fi
  log "install uv"
  curl -fsSL https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  ok "uv $(uv --version)"
}

install_nvm_node() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    log "install nvm"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  else
    ok "nvm present"
  fi
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  if ! nvm ls --no-colors 2>/dev/null | grep -q 'v24\|v22\|v20'; then
    log "install node LTS via nvm"
    nvm install --lts
    nvm alias default 'lts/*'
  else
    ok "node already via nvm"
  fi
  nvm use default >/dev/null 2>&1 || nvm use --lts >/dev/null 2>&1 || true
  ok "node $(node --version) npm $(npm --version)"
  # corepack for pnpm/yarn without global npm pollution
  if have corepack; then
    corepack enable >/dev/null 2>&1 || true
    ok "corepack enabled (pnpm/yarn on demand)"
  fi
}

install_bun() {
  if have bun; then ok "bun $(bun --version)"; return; fi
  log "install bun"
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  ok "bun $(bun --version)"
}

install_direnv() {
  if have direnv; then ok "direnv $(direnv version)"; return; fi
  log "install direnv"
  local ver arch bin
  ver="$(github_latest_tag direnv/direnv)"
  [[ -n "$ver" ]] || ver="2.36.0"
  case "$(uname -m)" in
    x86_64|amd64) arch="linux-amd64" ;;
    aarch64|arm64) arch="linux-arm64" ;;
    *) die "no direnv for $(uname -m)" ;;
  esac
  bin="$CACHE_DIR/direnv.${arch}"
  download "https://github.com/direnv/direnv/releases/download/v${ver}/direnv.${arch}" "$bin"
  install -m 755 "$bin" "$LOCAL_BIN/direnv"
  ok "direnv $($LOCAL_BIN/direnv version)"
}

install_starship() {
  if have starship; then ok "starship $(starship --version)"; return; fi
  log "install starship"
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$LOCAL_BIN"
  ok "starship $($LOCAL_BIN/starship --version)"
}

install_doppler() {
  if have doppler; then ok "doppler $(doppler --version 2>/dev/null | head -1)"; return; fi
  log "install Doppler CLI"
  local arch tgz
  arch="$(arch_go)"
  [[ "$arch" == "amd64" || "$arch" == "arm64" ]] || die "unsupported arch: $arch"
  tgz="$CACHE_DIR/doppler-cli_linux_${arch}.tar.gz"
  download "https://cli.doppler.com/download?os=linux&arch=${arch}&format=tar" "$tgz"
  # extract to temp dir cleanly
  local tmpd
  tmpd="$(mktemp -d)"
  tar -C "$tmpd" -xzf "$tgz"
  local bin
  bin="$(find "$tmpd" -type f -name doppler | head -1)"
  [[ -n "$bin" ]] || die "doppler binary not found in tarball"
  install -m 755 "$bin" "$LOCAL_BIN/doppler"
  rm -rf "$tmpd"
  ok "doppler $($LOCAL_BIN/doppler --version | head -1)"
}

install_docker() {
  [[ "$WITH_DOCKER" == "1" ]] || return 0
  if have docker; then ok "docker $(docker --version)"; return; fi
  if ! can_sudo; then
    warn "docker needs sudo — skipped (re-run with sudo rights or install manually)"
    return 0
  fi
  log "install Docker Engine"
  # official convenience script — single dependency: curl
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER" || true
  # compose plugin usually included
  ok "docker installed (log out/in for group docker)"
}

install_flutter() {
  [[ "$WITH_FLUTTER" == "1" ]] || return 0
  if [[ -x "$HOME/flutter/bin/flutter" ]]; then
    ok "flutter $($HOME/flutter/bin/flutter --version 2>/dev/null | head -1)"
    return
  fi
  log "install Flutter SDK → ~/flutter"
  local tgz="$CACHE_DIR/flutter_linux_stable.tar.xz"
  # pinless stable channel archive
  if [[ ! -f "$tgz" ]]; then
    download "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.32.0-stable.tar.xz" "$tgz" \
      || download "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.0-stable.tar.xz" "$tgz" \
      || warn "flutter download failed — install manually from https://docs.flutter.dev"
  fi
  if [[ -f "$tgz" ]]; then
    tar -C "$HOME" -xJf "$tgz"
    ok "flutter extracted"
    "$HOME/flutter/bin/flutter" --version | head -2 || true
  fi
}

install_herdr() {
  [[ "$WITH_HERDR" == "1" ]] || return 0
  if have herdr; then ok "herdr $(herdr --version 2>/dev/null | head -1)"; return; fi
  log "install herdr"
  if curl -fsSL https://herdr.dev/install.sh | bash; then
    export PATH="$HOME/.local/bin:$PATH"
    ok "herdr $(herdr --version 2>/dev/null | head -1 || echo installed)"
  else
    warn "herdr install script failed"
  fi
}

install_ccgram() {
  [[ "$WITH_CCGRAM" == "1" ]] || return 0
  export PATH="$HOME/.local/bin:$PATH"
  have uv || install_uv
  log "install ccgram (uv tool)"
  uv tool install --force ccgram || warn "ccgram install failed"
  ok "ccgram $(ccgram --version 2>/dev/null || echo installed)"
}


install_go() {
  if have go; then ok "go $(go version)"; return; fi
  log "install Go (user-space → ~/.local/go)"
  local ver arch tgz
  ver="$(curl -fsSL https://go.dev/VERSION?m=text | head -1 || true)"
  [[ -n "$ver" ]] || ver="go1.24.5"
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "no go for $(uname -m)" ;;
  esac
  tgz="$CACHE_DIR/${ver}.linux-${arch}.tar.gz"
  download "https://go.dev/dl/${ver}.linux-${arch}.tar.gz" "$tgz"
  rm -rf "$HOME/.local/go"
  tar -C "$HOME/.local" -xzf "$tgz"
  export PATH="$HOME/.local/go/bin:$PATH"
  export GOPATH="${GOPATH:-$HOME/go}"
  mkdir -p "$GOPATH"
  ln -sf "$HOME/.local/go/bin/go" "$LOCAL_BIN/go"
  ln -sf "$HOME/.local/go/bin/gofmt" "$LOCAL_BIN/gofmt" 2>/dev/null || true
  ok "go $(go version)"
}

install_opencode() {
  if have opencode; then ok "opencode $(opencode --version 2>/dev/null | head -1)"; return; fi
  log "install OpenCode"
  if curl -fsSL https://opencode.ai/install | bash; then
    export PATH="$HOME/.opencode/bin:$PATH"
    ln -sf "$HOME/.opencode/bin/opencode" "$LOCAL_BIN/opencode" 2>/dev/null || true
    ok "opencode $(opencode --version 2>/dev/null | head -1 || echo installed)"
  else
    warn "opencode install failed"
  fi
}

install_typescript() {
  # Ensure TS 7 available via bun
  if have bun; then
    log "pin TypeScript 7 (bun)"
    bunx --bun typescript@7 --version >/dev/null 2>&1 || bunx typescript@7 --version >/dev/null 2>&1 || true
    ok "typescript via bunx: $(bunx tsc --version 2>/dev/null || echo ts7)"
  fi
}


install_project_layout() {
  log "project layout"
  mkdir -p "$HOME/projects"/{web,api,mobile,scripts,templates}
  if [[ ! -f "$HOME/projects/README.md" ]]; then
    cat > "$HOME/projects/README.md" <<'EOF'
# projects

Default workspace root for linux-devkit.

```
projects/
  web/       # frontend
  api/       # backends
  mobile/    # flutter / native
  scripts/   # helpers
  templates/ # starter copies
```

Create a new app:
```bash
devkit new web my-app
# or
mkdir -p ~/projects/web/my-app && cd $_
```
EOF
  fi
  ok "~/projects ready"
}

install_devkit_cli() {
  log "install devkit helper CLI"
  if [[ -f "$HOME/linux-devkit/scripts/devkit" ]]; then
    install -m 755 "$HOME/linux-devkit/scripts/devkit" "$LOCAL_BIN/devkit"
    ok "devkit CLI (full)"
    printf '%s\n' "$PROFILE" > "$DEVKIT_HOME/profile"
    printf '%s\n' "$DEVKIT_VERSION" > "$DEVKIT_HOME/version"
    [[ -f "$HOME/linux-devkit/projects.yaml" ]] && cp -f "$HOME/linux-devkit/projects.yaml" "$DEVKIT_HOME/projects.yaml" || true
    return 0
  fi
  cat > "$LOCAL_BIN/devkit" <<'EOF'
#!/usr/bin/env bash
# thin helper after linux-devkit install
set -euo pipefail
cmd="${1:-help}"
shift || true
case "$cmd" in
  doctor)
    echo "linux-devkit doctor"
    for c in git curl gh jq rg fd fzf uv node npm bun python3 docker flutter herdr doppler direnv starship; do
      if command -v "$c" >/dev/null 2>&1; then
        printf '  ✓ %-12s %s\n' "$c" "$(command -v "$c")"
      else
        printf '  · %-12s (missing)\n' "$c"
      fi
    done
    ;;
  new)
    kind="${1:-}"; name="${2:-}"
    [[ -n "$kind" && -n "$name" ]] || { echo "usage: devkit new <web|api|mobile|python> <name>"; exit 1; }
    root="$HOME/projects"
    case "$kind" in
      web) dir="$root/web/$name"; mkdir -p "$dir"; (cd "$dir" && npm create vite@latest . -- --template react-ts) || true ;;
      api) dir="$root/api/$name"; mkdir -p "$dir"; (cd "$dir" && npm init -y && npm pkg set type=module) ;;
      mobile) dir="$root/mobile/$name"; mkdir -p "$root/mobile"; flutter create "$dir" ;;
      python) dir="$root/api/$name"; mkdir -p "$dir"; (cd "$dir" && uv init) ;;
      *) echo "unknown kind: $kind"; exit 1 ;;
    esac
    echo "created: $dir"
    ;;
  update)
    echo "Re-run installer to update tools:"
    echo "  bash ~/.linux-devkit/install.sh --profile ${DEVKIT_PROFILE:-default} -y"
    ;;
  help|*)
    cat <<H
devkit — linux-devkit helper

  devkit doctor          check installed tools
  devkit new web NAME    scaffold vite react-ts
  devkit new api NAME    scaffold node package
  devkit new mobile NAME flutter create
  devkit new python NAME uv init
  devkit update          how to re-run installer
H
    ;;
esac
EOF
  chmod 755 "$LOCAL_BIN/devkit"
  # keep a copy of this installer for re-runs
  if [[ -f "${BASH_SOURCE[0]}" ]]; then
    cp -f "${BASH_SOURCE[0]}" "$DEVKIT_HOME/install.sh" 2>/dev/null || true
    chmod 755 "$DEVKIT_HOME/install.sh" 2>/dev/null || true
  fi
  printf '%s\n' "$PROFILE" > "$DEVKIT_HOME/profile"
  printf '%s\n' "$DEVKIT_VERSION" > "$DEVKIT_HOME/version"
  ok "devkit CLI → ~/.local/bin/devkit"
}

write_cloud_init_snippet() {
  cat > "$DEVKIT_HOME/cloud-init-snippet.yaml" <<EOF
#cloud-config
# Paste into cloud-init user-data for a new VM (DigitalOcean, Hetzner, Proxmox, …)
# No interactive prompts. After first boot: ssh in and run \`devkit doctor\`.

package_update: true
package_upgrade: false

packages:
  - curl
  - ca-certificates
  - git
  - unzip
  - tar
  - xz-utils
  - build-essential
  - python3
  - jq
  - tmux

runcmd:
  - |
    set -e
    export HOME=/home/\${SUDO_USER:-\$(id -un)}
    # if cloud-init runs as root, install for the first non-root user
    U=\$(getent passwd 1000 | cut -d: -f1 || true)
    if [ -n "\$U" ]; then
      sudo -u "\$U" -H bash -lc 'curl -fsSL https://raw.githubusercontent.com/bedulweb/devkit/main/install.sh | bash -s -- --profile default --with-docker -y'
    fi
EOF
  ok "cloud-init snippet → $DEVKIT_HOME/cloud-init-snippet.yaml"
}

# ── main ──────────────────────────────────────────────────────────────
main() {
  log "linux-devkit v${DEVKIT_VERSION}  profile=${PROFILE}"
  need_cmd curl
  need_cmd tar
  ensure_dirs
  ensure_path_snippet
  configure_git_identity

  install_apt_base

  # always (all profiles)
  install_gh
  install_jq
  install_rg
  install_fd
  install_fzf
  install_uv
  install_nvm_node

  if [[ "$PROFILE" != "minimal" ]]; then
    install_bun
    install_typescript
    install_direnv
    install_starship
    [[ "$WITH_DOPPLER" == "1" ]] && install_doppler
    install_go
    install_opencode
  fi

  install_docker
  install_flutter
  install_herdr
  install_ccgram
  install_project_layout
  install_devkit_cli
  write_cloud_init_snippet

  # Agent skills pack (optional, needs network + npx/bun)
  if [[ "$PROFILE" != "minimal" ]] && [[ -x "$HOME/linux-devkit/scripts/install-skills.sh" || -x "$DEVKIT_HOME/../linux-devkit/scripts/install-skills.sh" ]]; then
    log "agent skills pack"
    if [[ -x "$HOME/linux-devkit/scripts/install-skills.sh" ]]; then
      bash "$HOME/linux-devkit/scripts/install-skills.sh" || warn "skills pack failed"
    fi
  fi


  echo
  log "done"
  echo
  cat <<EOF
${C_BOLD}Next steps${C_RESET}
  1. Open a new shell (or: source ~/.bashrc)
  2. Run:  ${C_CYAN}devkit doctor${C_RESET}
  3. Login tools you need:
       gh auth login
       doppler configure set token "\$DOPPLER_TOKEN"   # dari ~/.devkit.env
  4. New project:
       devkit new web my-app
       devkit new mobile my_app

${C_DIM}Re-run anytime (idempotent):${C_RESET}
  bash ~/.linux-devkit/install.sh --profile ${PROFILE} -y

${C_DIM}Fresh VM / cloud-init:${C_RESET}
  see ~/.linux-devkit/cloud-init-snippet.yaml
EOF
}

main "$@"
