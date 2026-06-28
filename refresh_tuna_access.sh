#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
ACCESS_ENV="$STATE_DIR/tuna_access_latest.env"
ACCESS_TXT="$STATE_DIR/tuna_access_latest.txt"
TUNA_CONFIG="$BASE_DIR/tuna_config.env"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "telegram_commands"

if [[ -f "$TUNA_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$TUNA_CONFIG"
fi

TUNA_UPDATE_WAIT_SECONDS="${TUNA_UPDATE_WAIT_SECONDS:-120}"
TUNA_RESTART_DELAY_SECONDS="${TUNA_RESTART_DELAY_SECONDS:-5}"

access_is_complete() {
  [[ -f "$ACCESS_ENV" ]] || return 1
  local host="" port="" command="" password="" tunnel_mode=""
  # shellcheck disable=SC1090
  source "$ACCESS_ENV"
  host="${TUNA_ACCESS_HOST:-}"
  port="${TUNA_ACCESS_PORT:-}"
  command="${TUNA_ACCESS_SSH_COMMAND:-}"
  password="${TUNA_ACCESS_PASSWORD:-}"
  tunnel_mode="${TUNA_ACCESS_TUNNEL_MODE:-}"

  [[ -n "$host" && -n "$port" && -n "$command" ]] || return 1
  if [[ "$tunnel_mode" == "ssh" ]]; then
    [[ -n "$password" ]] || return 1
  fi
  return 0
}

log "telegram update requested: refreshing tuna access"

if pgrep -af '[t]una .* (ssh|tcp)|[t]una (ssh|tcp)' >/dev/null 2>&1; then
  pkill -TERM -f '[t]una .* (ssh|tcp)|[t]una (ssh|tcp)' || true
fi
if pgrep -af '[c]apture_tuna_access.py.*--mode' >/dev/null 2>&1; then
  pkill -TERM -f '[c]apture_tuna_access.py.*--mode' || true
fi

sleep "$TUNA_RESTART_DELAY_SECONDS"

if ! pgrep -af '[t]una_headless.sh' >/dev/null 2>&1; then
  systemctl start autostart-tuna-backup.service >/dev/null 2>&1 || true
fi

deadline=$((SECONDS + TUNA_UPDATE_WAIT_SECONDS))
while (( SECONDS < deadline )); do
  if access_is_complete; then
    log "telegram update completed: access file refreshed"
    cat "$ACCESS_TXT"
    exit 0
  fi
  sleep 2
done

log "telegram update timed out waiting for fresh tuna access"
if [[ -f "$ACCESS_TXT" ]]; then
  cat "$ACCESS_TXT"
fi
exit 1
