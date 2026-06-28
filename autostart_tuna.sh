#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
MAIL_CONFIG="$BASE_DIR/mail_config.env"
TUNA_CONFIG="$BASE_DIR/tuna_config.env"
TUNA_BIN="$(command -v tuna || true)"
REPORT_FILE="$STATE_DIR/boot_report_$(date +%Y%m%d_%H%M%S).txt"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id)"
TERMINAL_STAMP="$STATE_DIR/tuna_terminal.boot_id"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "autostart"

if [[ -f "$TUNA_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$TUNA_CONFIG"
fi

TUNA_RESTART_DELAY_SECONDS="${TUNA_RESTART_DELAY_SECONDS:-5}"
MAIL_SEND_RETRIES="${MAIL_SEND_RETRIES:-8}"
MAIL_SEND_RETRY_DELAY_SECONDS="${MAIL_SEND_RETRY_DELAY_SECONDS:-30}"

create_report() {
  {
    echo "Boot report"
    echo "==========="
    echo "Generated at: $(date --iso-8601=seconds)"
    echo "Hostname: $(hostname)"
    echo "User: $(id -un)"
    echo "Working directory: $BASE_DIR"
    echo "Desktop: ${XDG_CURRENT_DESKTOP:-unknown}"
    echo "Session: ${DESKTOP_SESSION:-unknown}"
    echo "Display: ${DISPLAY:-not-set}"
    echo "Shell: ${SHELL:-unknown}"
    echo "Tuna binary: ${TUNA_BIN:-not-found}"
    echo "Tuna launch mode: direct without proxy environment"
    echo "Telegram delivery mode: local proxy 127.0.0.1:12334 when reachable"
    echo
    echo "System"
    echo "------"
    uname -a
    echo
    echo "IP addresses"
    echo "------------"
    hostname -I 2>/dev/null || true
    echo
    ip -brief addr 2>/dev/null || true
    echo
    echo "TigerVNC status"
    echo "---------------"
    systemctl status tigervncserver@:1.service --no-pager 2>&1 || true
    echo
    echo "Autostart desktop file"
    echo "----------------------"
    sed -n '1,200p' "$BASE_DIR/tuna-ssh.desktop" 2>/dev/null || true
    echo
    echo "Autostart script"
    echo "----------------"
    sed -n '1,240p' "$BASE_DIR/autostart_tuna.sh" 2>/dev/null || true
    echo
    echo "Mail config"
    echo "-----------"
    if [[ -f "$MAIL_CONFIG" ]]; then
      sed -E 's/^(SMTP_PASSWORD=).*/\1[hidden]/' "$MAIL_CONFIG"
    else
      echo "mail_config.env is missing"
    fi
  } >"$REPORT_FILE"
}

send_report_async() {
  if [[ "${AUTOSTART_SKIP_EMAIL:-0}" == "1" ]]; then
    log "Email sending skipped by AUTOSTART_SKIP_EMAIL=1"
    return 0
  fi

  if [[ ! -f "$MAIL_CONFIG" ]]; then
    log "mail_config.env not found, skipping email"
    return 0
  fi

  (
    local attempt=1
    while (( attempt <= MAIL_SEND_RETRIES )); do
      if python3 "$BASE_DIR/send_boot_report.py" "$REPORT_FILE" "$MAIL_CONFIG" >>"$(current_log_file)" 2>&1; then
        log "Boot report email step completed on attempt ${attempt}"
        return 0
      fi
      log "Boot report email attempt ${attempt} failed"
      (( attempt++ ))
      sleep "$MAIL_SEND_RETRY_DELAY_SECONDS"
    done

    log "Boot report email failed after ${MAIL_SEND_RETRIES} attempts"
  ) &
}

open_terminal() {
  if [[ "${AUTOSTART_SKIP_TERMINAL:-0}" == "1" ]]; then
    log "Terminal launch skipped by AUTOSTART_SKIP_TERMINAL=1"
    return 0
  fi

  if [[ -z "$TUNA_BIN" ]]; then
    log "tuna binary not found, cannot open terminal"
    return 1
  fi

  if ! command -v gnome-terminal >/dev/null 2>&1; then
    log "gnome-terminal not found, cannot open terminal"
    return 1
  fi

  if [[ -f "$TERMINAL_STAMP" ]] && [[ "$(cat "$TERMINAL_STAMP" 2>/dev/null)" == "$BOOT_ID" ]]; then
    log "tuna terminal already started for current boot"
    return 0
  fi

  printf '%s\n' "$BOOT_ID" >"$TERMINAL_STAMP"
  gnome-terminal --title="tuna ssh" -- bash -lc "exec '$AUTOSTART_DIR/tuna_interactive.sh'" &
  log "gnome-terminal launched with tuna ssh in direct mode without proxy environment"
}

log "Autostart script started"
create_report
log "Boot report created at $REPORT_FILE"
send_report_async
open_terminal || true
log "Autostart script finished"
