#!/usr/bin/env bash
# Thin wrapper → full setup (run.sh)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/bedulweb/devkit/main/bootstrap-vps.sh | bash
#
# With secrets:
#   export GH_TOKEN=...
#   export DOPPLER_TOKEN=dp.st.xxx
#   export DOPPLER_PROJECT=wazapin-platform
#   export DOPPLER_CONFIG=dev
#   curl -fsSL .../bootstrap-vps.sh | bash
set -euo pipefail

KIT_REPO="${DEVKIT_KIT_REPO:-https://github.com/bedulweb/devkit.git}"
export PATH="${HOME}/.local/bin:${PATH}"

if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates
  else
    echo "Need git + curl. Install: sudo apt-get install -y git curl" >&2
    exit 1
  fi
fi

if [[ -f "${HOME}/linux-devkit/run.sh" ]]; then
  git -C "${HOME}/linux-devkit" pull --ff-only 2>/dev/null || true
else
  git clone --depth 1 "${KIT_REPO}" "${HOME}/linux-devkit"
fi

exec bash "${HOME}/linux-devkit/run.sh"
