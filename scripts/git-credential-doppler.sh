#!/usr/bin/env bash
# Git credential helper for GitHub HTTPS remotes.
#
# The GitHub token is read from Doppler only when Git asks for credentials.
# No GitHub token is written to ~/.gitconfig or a credential file.
set -euo pipefail

case "${1:-}" in
  get) ;;
  store|erase|*) exit 0 ;;
esac

input="$(cat)"
[[ "$input" == *"protocol=https"* ]] || exit 0
[[ "$input" == *"host=github.com"* ]] || exit 0

project="${DEVKIT_GITHUB_DOPPLER_PROJECT:-vendor-access}"
config="${DEVKIT_GITHUB_DOPPLER_CONFIG:-prd}"

doppler run --project="$project" --config="$config" -- sh -c '
  token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  test -n "$token"
  printf "username=x-access-token\npassword=%s\n" "$token"
'
