#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
CONFIG_FILE="$BASE_DIR/vnc_config.env"
LOCK_FILE="$STATE_DIR/vnc_keepalive.lock"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "vnc_keepalive"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

VNC_DISPLAY="${VNC_DISPLAY:-:1}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
VNC_DEPTH="${VNC_DEPTH:-24}"
VNC_CHECK_INTERVAL_SECONDS="${VNC_CHECK_INTERVAL_SECONDS:-30}"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  exit 0
fi

vnc_running() {
  pgrep -af "Xtigervnc ${VNC_DISPLAY}" >/dev/null 2>&1 || \
    pgrep -af "vncserver ${VNC_DISPLAY}" >/dev/null 2>&1
}

start_vnc() {
  log "Starting VNC on ${VNC_DISPLAY} with geometry ${VNC_GEOMETRY} and depth ${VNC_DEPTH}"
  /usr/bin/vncserver "$VNC_DISPLAY" -depth "$VNC_DEPTH" -geometry "$VNC_GEOMETRY" >>"$(current_log_file)" 2>&1
}

log "VNC keepalive started"

while true; do
  if vnc_running; then
    log "VNC already running on ${VNC_DISPLAY}"
  else
    start_vnc || log "Failed to start VNC on ${VNC_DISPLAY}"
  fi
  sleep "$VNC_CHECK_INTERVAL_SECONDS"
done
