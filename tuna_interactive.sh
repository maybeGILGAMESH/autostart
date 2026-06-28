#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
LOCK_FILE="$STATE_DIR/tuna_runtime.lock"
CONFIG_FILE="$BASE_DIR/tuna_config.env"
TUNA_BIN="$(command -v tuna || true)"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "tuna_interactive"
# shellcheck disable=SC1091
source "$BASE_DIR/env_helpers.sh"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

TUNA_RESTART_DELAY_SECONDS="${TUNA_RESTART_DELAY_SECONDS:-5}"

if [[ -z "$TUNA_BIN" ]]; then
  log "tuna binary not found"
  exec bash
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "tuna runtime lock is already held by another process"
  printf 'tuna tunnel is already running in another process.\n'
  exec bash
fi

while true; do
  log "starting tuna tunnel in interactive terminal without proxy environment"
  set +e
  run_without_proxy python3 "$BASE_DIR/capture_tuna_access.py" --mode interactive --echo --tuna-bin "$TUNA_BIN"
  status=$?
  set -e
  log "tuna tunnel exited with status $status"
  printf '\n[tuna tunnel exited with code %s]\n' "$status"
  sleep "$TUNA_RESTART_DELAY_SECONDS"
done
