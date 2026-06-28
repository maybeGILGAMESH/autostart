#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
CONFIG_FILE="$BASE_DIR/health_config.env"
MAIL_CONFIG="$BASE_DIR/mail_config.env"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "health_check"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

VNC_DISPLAY="${VNC_DISPLAY:-:1}"
BOT_HEARTBEAT_FILE="${BOT_HEARTBEAT_FILE:-$STATE_DIR/test_env_bot.heartbeat}"
BOT_HEARTBEAT_MAX_AGE_SECONDS="${BOT_HEARTBEAT_MAX_AGE_SECONDS:-900}"
AUTO_REBOOT_ENABLED="${AUTO_REBOOT_ENABLED:-1}"
HEALTHCHECK_RECOVERY_WAIT_SECONDS="${HEALTHCHECK_RECOVERY_WAIT_SECONDS:-45}"

send_alert() {
  local subject="$1"
  local body="$2"
  python3 "$BASE_DIR/send_status_email.py" "$MAIL_CONFIG" "$subject" "$body" >>"$(current_log_file)" 2>&1 || true
}

service_ok() {
  systemctl is-active --quiet "$1"
}

vnc_ok() {
  pgrep -af "Xtigervnc ${VNC_DISPLAY}" >/dev/null 2>&1 && ss -ltnp | grep -q '127.0.0.1:5901'
}


tuna_ok() {
  pgrep -af '[t]una (ssh|tcp)' >/dev/null 2>&1
}

bot_ok() {
  service_ok autostart-test-bot.service || return 1
  [[ -f "$BOT_HEARTBEAT_FILE" ]] || return 1
  local now ts
  now="$(date +%s)"
  ts="$(stat -c %Y "$BOT_HEARTBEAT_FILE" 2>/dev/null || echo 0)"
  (( now - ts <= BOT_HEARTBEAT_MAX_AGE_SECONDS ))
}

collect_failures() {
  local failures=()
  vnc_ok || failures+=("vnc")
  tuna_ok || failures+=("tuna")
  bot_ok || failures+=("test-bot")
  printf '%s\n' "${failures[@]}"
}

restart_stack() {
  log "Trying self-heal sequence"
  systemctl restart autostart-vnc-keepalive.service || true
  systemctl restart autostart-test-bot.service || true
  systemctl restart autostart-tuna-backup.service || true
  "$BASE_DIR/fallback_orchestrator.sh" >>"$(current_log_file)" 2>&1 || true
}

log "Health check started"
mapfile -t failures_before < <(collect_failures)

if (( ${#failures_before[@]} == 0 )); then
  log "Health check passed"
  exit 0
fi

log "Initial failures: ${failures_before[*]}"
send_alert "Health check failure on {hostname}" "Initial failures detected: ${failures_before[*]}. Starting self-heal sequence."
restart_stack
sleep "$HEALTHCHECK_RECOVERY_WAIT_SECONDS"
mapfile -t failures_after < <(collect_failures)

if (( ${#failures_after[@]} == 0 )); then
  log "Self-heal succeeded"
  send_alert "Health check recovered on {hostname}" "Self-heal recovered all components after initial failures: ${failures_before[*]}."
  exit 0
fi

log "Failures after self-heal: ${failures_after[*]}"
send_alert "Health check critical on {hostname}" "Components still down after self-heal: ${failures_after[*]}."

if [[ "$AUTO_REBOOT_ENABLED" == "1" ]]; then
  log "AUTO_REBOOT_ENABLED=1, rebooting system"
  send_alert "Auto reboot triggered on {hostname}" "Auto reboot is being triggered because these components are still down: ${failures_after[*]}."
  systemctl reboot
else
  log "AUTO_REBOOT_ENABLED=0, reboot skipped"
  exit 1
fi
