#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="$repo_root/scripts/install-depot.sh"

bash -n "$installer"
grep -Fq 'sha256sum' "$installer"
grep -Fq 'DEVKIT_DEPOT_DOPPLER_PROJECT:-infrastructure' "$installer"
grep -Fq 'DEVKIT_DEPOT_DOPPLER_CONFIG:-prd' "$installer"
grep -Fq 'doppler run' "$installer"

echo "install-depot contract: OK"
