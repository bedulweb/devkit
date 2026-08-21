#!/usr/bin/env bash
# Restore Grok configuration and AI for UI skills from Doppler.
set -euo pipefail
PROJECT="${GROK_DOPPLER_PROJECT:-developer-workstation}"
CONFIG="${GROK_DOPPLER_CONFIG:-dev}"
KIT="${DEVKIT_HOME_REPO:-$HOME/linux-devkit}"
GROK_HOME="${GROK_HOME:-$HOME/.grok}"

command -v doppler >/dev/null 2>&1 || { echo 'Doppler CLI is required.' >&2; exit 1; }
command -v grok >/dev/null 2>&1 || { echo 'Grok CLI is required.' >&2; exit 1; }
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
command -v npx >/dev/null 2>&1 || { echo 'npx is required. Install Node.js with the devkit installer.' >&2; exit 1; }
NPX="$(command -v npx)"
TEMPLATE="$KIT/config.grok.toml"
[[ -f "$TEMPLATE" ]] || { echo "Missing Grok config template: $TEMPLATE" >&2; exit 1; }
mkdir -p "$GROK_HOME"
if [[ -f "$GROK_HOME/config.toml" && ! -f "$GROK_HOME/config.toml.devkit-backup" ]]; then
  cp "$GROK_HOME/config.toml" "$GROK_HOME/config.toml.devkit-backup"
fi
install -m 600 "$TEMPLATE" "$GROK_HOME/config.toml"

doppler run --project="$PROJECT" --config="$CONFIG" -- \
  bash -c 'exec "$1" --yes @aiforui/install --token="$AIFORUI_INSTALL_TOKEN" --yes --global' _ "$NPX"

echo "Grok configuration is ready. Start it with: grok"
