#!/usr/bin/env bash
# stop-dev.sh — stop OpenCode (service + TUI sessions) and aiwa dev servers.
#
#   bash ~/linux-devkit/scripts/stop-dev.sh [opencode|aiwa|all] [--dry-run]
#
# Matches by process pattern + well-known aiwa ports, spares its own process
# tree so the calling session survives. TERM first, KILL after grace period.
set -uo pipefail

MODE="all"
DRY_RUN=0
for a in "$@"; do
  case "$a" in
    opencode|aiwa|all) MODE="$a" ;;
    --dry-run|-n) DRY_RUN=1 ;;
    *) echo "usage: stop-dev.sh [opencode|aiwa|all] [--dry-run]" >&2; exit 1 ;;
  esac
done

GRACE="${DEVKIT_STOP_GRACE:-5}"
AIWA_PORTS="${DEVKIT_AIWA_PORTS:-30280 8787 5191}"

# ── spare own process tree (self + ancestors) ─────────────────────────
declare -A SPARE
_p="$$"
while [[ -n "${_p:-}" && "$_p" -gt 1 ]]; do
  SPARE["$_p"]=1
  _p="$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')"
done

collect() { # collect <array-name> <pgrep-pattern>...
  local -n _out="$1"; shift
  local pat pid
  for pat in "$@"; do
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      [[ -n "${SPARE[$pid]:-}" ]] && continue
      [[ "$pid" == "1" ]] && continue
      _out+=("$pid")
    done < <(pgrep -f "$pat" 2>/dev/null || true)
  done
}

collect_ports() { # collect_ports <array-name> <port>...
  local -n _out="$1"; shift
  local port pid
  for port in "$@"; do
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      [[ -n "${SPARE[$pid]:-}" ]] && continue
      [[ "$pid" == "1" ]] && continue
      _out+=("$pid")
    done < <(ss -tlnp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" | grep -oP 'pid=\K[0-9]+' | sort -u || true)
  done
}

PIDS=()
case "$MODE" in
  opencode|all)
    # opencode TUI + serve --service (exe on some installs)
    collect PIDS 'opencode(\.exe)?( |$)' 'opencode\.exe serve'
    ;;
esac
case "$MODE" in
  aiwa|all)
    # aiwa dev servers: astro/vite/vite-plus/workerd under aiwa tree + known ports
    # shellcheck disable=SC2206
    collect_ports PIDS $AIWA_PORTS
    collect PIDS 'astro dev' 'vite-plus' '/aiwa/' 'workerd.*storefront'
    ;;
esac

# dedupe
mapfile -t PIDS < <(printf '%s\n' "${PIDS[@]}" | sort -un)

if [[ "${#PIDS[@]}" == "0" ]]; then
  echo "stop-dev [$MODE]: nothing matched"
  exit 0
fi

echo "stop-dev [$MODE]: matched ${#PIDS[@]} process(es)"
for pid in "${PIDS[@]}"; do
  cmdline="<exited>"
  [[ -r "/proc/$pid/cmdline" ]] && cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-120)"
  printf '  %-7s %s\n' "$pid" "$cmdline"
done

if [[ "$DRY_RUN" == "1" ]]; then
  echo "dry-run: no signals sent"
  exit 0
fi

kill -TERM "${PIDS[@]}" 2>/dev/null || true
for ((i = 0; i < GRACE; i++)); do
  alive=()
  for pid in "${PIDS[@]}"; do kill -0 "$pid" 2>/dev/null && alive+=("$pid"); done
  [[ "${#alive[@]}" == "0" ]] && { echo "stopped gracefully"; exit 0; }
  sleep 1
done
kill -KILL "${alive[@]}" 2>/dev/null || true
sleep 1
left=()
for pid in "${alive[@]}"; do kill -0 "$pid" 2>/dev/null && left+=("$pid"); done
if [[ "${#left[@]}" == "0" ]]; then
  echo "stopped (SIGKILL needed for: ${alive[*]})"
else
  echo "still alive (check manually): ${left[*]}" >&2
  exit 1
fi
