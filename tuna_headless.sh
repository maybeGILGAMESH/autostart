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
init_hourly_logging "tuna_headless"
# shellcheck disable=SC1091
source "$BASE_DIR/env_helpers.sh"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

TUNA_RESTART_DELAY_SECONDS="${TUNA_RESTART_DELAY_SECONDS:-5}"
TUNA_HEADLESS_IDLE_SECONDS="${TUNA_HEADLESS_IDLE_SECONDS:-15}"

if [[ -z "$TUNA_BIN" ]]; then
  log "tuna binary not found"
  exit 1
fi

while true; do
  if pgrep -af '[t]una (ssh|tcp)' >/dev/null 2>&1; then
    log "tuna tunnel already running, headless backup is waiting"
    sleep "$TUNA_HEADLESS_IDLE_SECONDS"
    continue
  fi

  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "tuna runtime lock is busy, headless backup is waiting"
    sleep "$TUNA_HEADLESS_IDLE_SECONDS"
    continue
  fi

  log "starting tuna tunnel in headless backup mode without proxy environment"
  set +e
  run_without_proxy python3 "$BASE_DIR/capture_tuna_access.py" --mode headless --tuna-bin "$TUNA_BIN"
  status=$?
  set -e
  log "tuna tunnel in headless backup mode exited with status $status"
  flock -u 9
  sleep "$TUNA_RESTART_DELAY_SECONDS"
done
