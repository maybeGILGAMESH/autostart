#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
MAIL_CONFIG="$BASE_DIR/mail_config.env"
CONFIG_FILE="$BASE_DIR/fallback_config.env"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "fallback_orchestrator"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

VNC_DISPLAY="${VNC_DISPLAY:-:1}"
VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
VNC_DEPTH="${VNC_DEPTH:-24}"
FALLBACK_INITIAL_DELAY_SECONDS="${FALLBACK_INITIAL_DELAY_SECONDS:-90}"
FALLBACK_DISPLAY_WAIT_SECONDS="${FALLBACK_DISPLAY_WAIT_SECONDS:-240}"
FALLBACK_ALERT_ON_RECOVERY="${FALLBACK_ALERT_ON_RECOVERY:-1}"
export DISPLAY="$VNC_DISPLAY"
export XAUTHORITY="${XAUTHORITY:-$AUTOSTART_XAUTHORITY}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$AUTOSTART_XDG_RUNTIME_DIR}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-$AUTOSTART_DBUS_SESSION_BUS_ADDRESS}"

send_alert() {
  local subject="$1"
  local body="$2"
  python3 "$BASE_DIR/send_status_email.py" "$MAIL_CONFIG" "$subject" "$body" >>"$(current_log_file)" 2>&1 || true
}

is_vnc_up() {
  pgrep -af "Xtigervnc ${VNC_DISPLAY}" >/dev/null 2>&1
}


is_tuna_up() {
  pgrep -af '[t]una (ssh|tcp)' >/dev/null 2>&1
}

wait_for_display() {
  local deadline=$((SECONDS + FALLBACK_DISPLAY_WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if DISPLAY="$VNC_DISPLAY" xset q >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

log "Fallback orchestrator started"
sleep "$FALLBACK_INITIAL_DELAY_SECONDS"

if ! is_vnc_up; then
  log "VNC is down, starting ${VNC_DISPLAY}"
  /usr/bin/vncserver "$VNC_DISPLAY" -depth "$VNC_DEPTH" -geometry "$VNC_GEOMETRY" >>"$(current_log_file)" 2>&1 || true
  send_alert "Fallback: VNC recovered on {hostname}" "Primary startup path did not bring VNC up. Fallback started ${VNC_DISPLAY}."
fi

if ! wait_for_display; then
  log "Display ${VNC_DISPLAY} is not ready after fallback wait"
  send_alert "Fallback: display not ready on {hostname}" "Display ${VNC_DISPLAY} did not become ready. Manual check recommended."
  exit 1
fi
log "VPN autostart is disabled; Hiddify and Outline are not started by fallback"

if ! is_tuna_up; then
  log "tuna tunnel is down, running fallback launch"
  send_alert "Fallback: tuna tunnel restart on {hostname}" "Primary startup path did not bring tuna tunnel up. Running launch script."
  "$BASE_DIR/autostart_tuna.sh" >>"$(current_log_file)" 2>&1 || true
fi

sleep 10

if is_tuna_up && [[ "$FALLBACK_ALERT_ON_RECOVERY" == "1" ]]; then
  send_alert "Fallback: startup recovered on {hostname}" "Fallback path recovered the startup chain. Components are now responding."
fi

log "Fallback orchestrator finished"
