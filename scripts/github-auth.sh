#!/usr/bin/env bash
# Run a command with GitHub PAT access from developer-workstation Doppler secrets.
set -euo pipefail
PROJECT="${DEVKIT_DOPPLER_PROJECT:-developer-workstation}"
CONFIG="${DEVKIT_DOPPLER_CONFIG:-dev}"

command -v doppler >/dev/null 2>&1 || { echo 'Doppler CLI is required.' >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo 'GitHub CLI is required.' >&2; exit 1; }

if [[ "${1:-}" == "--check" ]]; then
  exec doppler run --project="$PROJECT" --config="$CONFIG" -- \
    bash -c 'test -n "${GH_TOKEN:-}" && gh api user --jq .login'
fi

ASKPASS="$(cd "$(dirname "$0")" && pwd)/git-askpass.sh"
exec doppler run --project="$PROJECT" --config="$CONFIG" -- \
  env GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 "$@"
