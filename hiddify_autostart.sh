#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
CONFIG_FILE="$BASE_DIR/hiddify_config.env"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id)"
BOOT_STAMP="$STATE_DIR/hiddify_autostart.boot_id"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "hiddify_autostart"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

HIDDIFY_APPIMAGE="${HIDDIFY_APPIMAGE:-$AUTOSTART_HIDDIFY_APPIMAGE}"
HIDDIFY_PRESTART_DELAY_SECONDS="${HIDDIFY_PRESTART_DELAY_SECONDS:-5}"
HIDDIFY_FIRST_RUN_SECONDS="${HIDDIFY_FIRST_RUN_SECONDS:-15}"
HIDDIFY_RESTART_PAUSE_SECONDS="${HIDDIFY_RESTART_PAUSE_SECONDS:-5}"
HIDDIFY_WAIT_FOR_PROXY_SECONDS="${HIDDIFY_WAIT_FOR_PROXY_SECONDS:-60}"
HIDDIFY_DISPLAY="${DISPLAY:-${HIDDIFY_DISPLAY:-:1}}"
HIDDIFY_FORCE_RESTART="${HIDDIFY_FORCE_RESTART:-0}"

already_handled_this_boot() {
  [[ -f "$BOOT_STAMP" ]] && [[ "$(cat "$BOOT_STAMP" 2>/dev/null)" == "$BOOT_ID" ]]
}

wait_for_display() {
  local deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    if DISPLAY="$HIDDIFY_DISPLAY" xset q >/dev/null 2>&1; then
      log "Display $HIDDIFY_DISPLAY is ready"
      return 0
    fi
    sleep 2
  done

  log "Display $HIDDIFY_DISPLAY did not become ready"
  return 1
}

proxy_is_reachable() {
  if exec 3<>/dev/tcp/127.0.0.1/12334; then
    exec 3>&-
    exec 3<&-
    return 0
  fi

  return 1
}

wait_for_proxy() {
  local deadline=$((SECONDS + HIDDIFY_WAIT_FOR_PROXY_SECONDS))
  while (( SECONDS < deadline )); do
    if proxy_is_reachable; then
      log "Hiddify proxy port 12334 is reachable"
      return 0
    fi
    sleep 2
  done

  log "Hiddify proxy port 12334 did not become reachable"
  return 1
}

find_hiddify_pids() {
  ps -eo pid=,args= | awk -v app="$HIDDIFY_APPIMAGE" '
    index($0, app) > 0 || $0 ~ /\/tmp\/\.mount_Hiddif[^ ]*\/hiddify/ {
      print $1
    }
  '
}

stop_hiddify() {
  local pids
  pids="$(find_hiddify_pids || true)"
  if [[ -z "$pids" ]]; then
    log "No Hiddify processes to stop"
    return 0
  fi

  log "Stopping Hiddify processes: $(echo "$pids" | tr '\n' ' ')"
  while read -r pid; do
    [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
  done <<<"$pids"

  sleep 3

  pids="$(find_hiddify_pids || true)"
  if [[ -n "$pids" ]]; then
    log "Force killing Hiddify processes: $(echo "$pids" | tr '\n' ' ')"
    while read -r pid; do
      [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
    done <<<"$pids"
  fi
}

start_hiddify() {
  if [[ ! -x "$HIDDIFY_APPIMAGE" ]]; then
    log "Hiddify AppImage is missing or not executable: $HIDDIFY_APPIMAGE"
    return 1
  fi

  log "Starting Hiddify from $HIDDIFY_APPIMAGE on display $HIDDIFY_DISPLAY"
  nohup env DISPLAY="$HIDDIFY_DISPLAY" HOME="$HOME" bash -lc 'cd "$(dirname "$1")"; exec "$1"' _ "$HIDDIFY_APPIMAGE" >>"$(current_log_file)" 2>&1 &
}

log "Hiddify autostart script started"

if [[ "${HIDDIFY_SKIP_AUTOSTART:-0}" == "1" ]]; then
  log "Skipped by HIDDIFY_SKIP_AUTOSTART=1"
  exit 0
fi

if already_handled_this_boot; then
  if [[ "$HIDDIFY_FORCE_RESTART" == "1" ]]; then
    log "Forced Hiddify restart requested for current boot"
  elif proxy_is_reachable; then
    log "Already handled for current boot and proxy is reachable"
    exit 0
  else
    log "Already handled for current boot, but proxy is down; continuing with recovery"
  fi
fi

wait_for_display || exit 1
sleep "$HIDDIFY_PRESTART_DELAY_SECONDS"
start_hiddify || exit 1
sleep "$HIDDIFY_FIRST_RUN_SECONDS"
stop_hiddify
sleep "$HIDDIFY_RESTART_PAUSE_SECONDS"
start_hiddify || exit 1
if ! wait_for_proxy; then
  log "Hiddify proxy did not recover after restart cycle"
  exit 1
fi

printf '%s\n' "$BOOT_ID" >"$BOOT_STAMP"
log "Hiddify autostart script finished"
