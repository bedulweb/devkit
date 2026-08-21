#!/usr/bin/env bash
# Supply GitHub HTTPS credentials from GH_TOKEN injected by Doppler.
set -euo pipefail
case "${1:-}" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "${GH_TOKEN:?GH_TOKEN is required}" ;;
  *) exit 1 ;;
esac
