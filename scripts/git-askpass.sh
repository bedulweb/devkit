#!/usr/bin/env bash
# Supply GitHub HTTPS credentials from the Doppler-injected token.
# Accepts GH_TOKEN or GITHUB_TOKEN (whichever name the vault provides).
set -euo pipefail
case "${1:-}" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "${GH_TOKEN:-${GITHUB_TOKEN:?GitHub token is required (GH_TOKEN or GITHUB_TOKEN)}}" ;;
  *) exit 1 ;;
esac
