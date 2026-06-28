#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
MAIL_CONFIG="$BASE_DIR/mail_config.env"
MODE="${1:-send}"
HOSTNAME="$(hostname)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="$STATE_DIR/full_status_report_${TIMESTAMP}.txt"
TUNA_ACCESS_FILE="$STATE_DIR/tuna_access_latest.txt"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "full_status_report"

usage() {
  cat <<'EOF'
Usage:
  send_full_status_report.sh send
  send_full_status_report.sh preview
  send_full_status_report.sh mailto

Modes:
  send     Build full report, save it to generated/, and send via email/TG config.
  preview  Build full report, save it to generated/, and print it without sending.
  mailto   Build full report, save it to generated/, and open a prefilled mail draft in Firefox/default mail handler.
EOF
}

is_active_text() {
  local unit="$1"
  systemctl is-active "$unit" 2>/dev/null || true
}

is_enabled_text() {
  local unit="$1"
  systemctl is-enabled "$unit" 2>/dev/null || true
}

has_process() {
  local pattern="$1"
  if pgrep -af "$pattern" >/dev/null 2>&1; then
    echo "running"
  else
    echo "stopped"
  fi
}

has_port() {
  local port_pattern="$1"
  if ss -ltnp 2>/dev/null | grep -q "$port_pattern"; then
    echo "listening"
  else
    echo "not-listening"
  fi
}

tuna_port_lines() {
  ss -ltnp 2>/dev/null | grep -i 'users:(("tuna"' || true
}

mail_to_address() {
  local value
  value="$(sed -n 's/^MAIL_TO=//p' "$MAIL_CONFIG" 2>/dev/null | tail -n 1)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf 'najmutdinov.r@yandex.ru\n'
  fi
}

short_status_line() {
  printf 'VNC=%s, Hiddify=%s, TunaAny=%s, TunaSSH=%s, TunaTCP=%s, TunaHTTP=%s, Bot=%s' \
    "$(has_process 'Xtigervnc :1')" \
    "$(has_process 'Hiddify-Linux-x64.AppImage|/hiddify')" \
    "$(has_process '[t]una( |$)')" \
    "$(has_process '[t]una ssh')" \
    "$(has_process '[t]una tcp')" \
    "$(has_process '[t]una http')" \
    "$(has_process "$AUTOSTART_DIR/test_env_bot.py")"
}

cron_autostart_text() {
  if crontab -l 2>/dev/null | grep -q "$AUTOSTART_DIR/cron_reboot.sh"; then
    echo "enabled"
  else
    echo "disabled"
  fi
}

open_mailto() {
  local recipient subject body mailto_url
  recipient="$(mail_to_address)"
  subject="Status report from ${HOSTNAME}"
  body="$(cat <<EOF
Status report

Generated at: $(date --iso-8601=seconds)
Hostname: $HOSTNAME
User: $(id -un)
Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || echo unknown)
Autostart: tuna=$([[ -L "$HOME/.config/autostart/tuna-ssh.desktop" ]] && echo enabled || echo disabled), hiddify=$([[ -L "$HOME/.config/autostart/hiddify-client.desktop" ]] && echo enabled || echo disabled), cron=$(cron_autostart_text)
Systemd:
  vnc=$(is_active_text autostart-vnc-keepalive.service)/$(is_enabled_text autostart-vnc-keepalive.service)
  fallback=$(is_active_text autostart-fallback.service)/$(is_enabled_text autostart-fallback.service)
  bot=$(is_active_text autostart-test-bot.service)/$(is_enabled_text autostart-test-bot.service)
  tuna=$(is_active_text autostart-tuna-backup.service)/$(is_enabled_text autostart-tuna-backup.service)
  health=$(is_active_text autostart-healthcheck.timer)/$(is_enabled_text autostart-healthcheck.timer)
  periodic_status=$(is_active_text autostart-periodic-status.timer)/$(is_enabled_text autostart-periodic-status.timer)
Components: $(short_status_line)
IP: $(hostname -I 2>/dev/null || echo unavailable)

Full report saved locally:
$REPORT_FILE
EOF
)"

  mailto_url="$(python3 - <<'PY' "$recipient" "$subject" "$body"
import sys
import urllib.parse

recipient = sys.argv[1]
subject = sys.argv[2]
body = sys.argv[3]
print(f"mailto:{recipient}?subject={urllib.parse.quote(subject)}&body={urllib.parse.quote(body)}")
PY
)"

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$mailto_url" >/dev/null 2>&1 &
  elif command -v firefox >/dev/null 2>&1; then
    firefox "$mailto_url" >/dev/null 2>&1 &
  else
    echo "No mailto opener found"
    exit 1
  fi

  log "Opened mailto draft for $recipient"
  printf 'Mail draft opened for: %s\n' "$recipient"
  printf 'Full report saved: %s\n' "$REPORT_FILE"
}

build_report() {
  {
    echo "Full system status report"
    echo "========================="
    echo "Generated at: $(date --iso-8601=seconds)"
    echo "Hostname: $HOSTNAME"
    echo "User: $(id -un)"
    echo "UID/GID: $(id -u)/$(id -g)"
    echo "Shell: ${SHELL:-unknown}"
    echo "PWD: $BASE_DIR"
    echo "Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || echo unknown)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo
    echo "Core components"
    echo "---------------"
    echo "VNC process: $(has_process 'Xtigervnc :1')"
    echo "VNC port 5901: $(has_port '127.0.0.1:5901')"
    echo "Hiddify process: $(has_process 'Hiddify-Linux-x64.AppImage|/hiddify')"
    echo "Hiddify proxy 12334: $(has_port '127.0.0.1:12334')"
    echo "tuna any process: $(has_process '[t]una( |$)')"
    echo "tuna ssh process: $(has_process '[t]una ssh')"
    echo "tuna tcp process: $(has_process '[t]una tcp')"
    echo "tuna http process: $(has_process '[t]una http')"
    echo "tuna launch mode: direct without proxy environment"
    echo "Telegram delivery mode: local proxy 127.0.0.1:12334 when reachable"
    echo "tuna listening ports:"
    tuna_port_lines
    if [[ -f "$TUNA_ACCESS_FILE" ]]; then
      echo "tuna latest access:"
      sed 's/^/  /' "$TUNA_ACCESS_FILE"
    else
      echo "tuna latest access: not captured yet"
    fi
    echo "Python test bot process: $(has_process "$AUTOSTART_DIR/test_env_bot.py")"
    echo
    echo "Autostart configuration"
    echo "-----------------------"
    if [[ -L "$HOME/.config/autostart/tuna-ssh.desktop" ]]; then
      echo "GNOME autostart tuna: enabled"
    else
      echo "GNOME autostart tuna: disabled"
    fi
    if [[ -L "$HOME/.config/autostart/hiddify-client.desktop" ]]; then
      echo "GNOME autostart Hiddify: enabled"
    else
      echo "GNOME autostart Hiddify: disabled"
    fi
    echo "crontab @reboot: $(cron_autostart_text)"
    echo
    echo "Systemd"
    echo "-------"
    echo "autostart-vnc-keepalive.service: active=$(is_active_text autostart-vnc-keepalive.service), enabled=$(is_enabled_text autostart-vnc-keepalive.service)"
    echo "autostart-fallback.service: active=$(is_active_text autostart-fallback.service), enabled=$(is_enabled_text autostart-fallback.service)"
    echo "autostart-test-bot.service: active=$(is_active_text autostart-test-bot.service), enabled=$(is_enabled_text autostart-test-bot.service)"
    echo "autostart-tuna-backup.service: active=$(is_active_text autostart-tuna-backup.service), enabled=$(is_enabled_text autostart-tuna-backup.service)"
    echo "autostart-healthcheck.timer: active=$(is_active_text autostart-healthcheck.timer), enabled=$(is_enabled_text autostart-healthcheck.timer)"
    echo "autostart-periodic-status.timer: active=$(is_active_text autostart-periodic-status.timer), enabled=$(is_enabled_text autostart-periodic-status.timer)"
    echo
    echo "Network"
    echo "-------"
    echo "IP addresses: $(hostname -I 2>/dev/null || echo unavailable)"
    echo
    ip -brief addr 2>/dev/null || true
    echo
    echo "Ports"
    echo "-----"
    ss -ltnp 2>/dev/null | grep -E ':(22|5901|12334)\b' || true
    echo
    echo "Processes"
    echo "---------"
    ps -ef | grep '[X]tigervnc' || true
    ps -ef | grep -i '[h]iddify' || true
    ps -ef | grep '[t]una ' || true
    ps -ef | grep '[t]una ssh' || true
    ps -ef | grep '[t]una tcp' || true
    ps -ef | grep '[t]una http' || true
    ps -ef | grep '[t]est_env_bot.py' || true
    echo
    echo "Recent logs"
    echo "-----------"
    echo "[autostart.log]"
    tail -n 10 "$LOG_DIR/autostart.log" 2>/dev/null || true
    echo
    echo "[hiddify_autostart.log]"
    tail -n 10 "$LOG_DIR/hiddify_autostart.log" 2>/dev/null || true
    echo
    echo "[tuna_headless.log]"
    tail -n 10 "$LOG_DIR/tuna_headless.log" 2>/dev/null || true
    echo
    echo "[autostart-tuna-backup.service]"
    journalctl --user -u autostart-tuna-backup.service -n 10 --no-pager 2>/dev/null || true
    echo
    echo "[test_env_bot_runtime.log]"
    tail -n 10 "$LOG_DIR/test_env_bot_runtime.log" 2>/dev/null || true
    echo
    echo "[health_check.log]"
    tail -n 10 "$LOG_DIR/health_check.log" 2>/dev/null || true
  } >"$REPORT_FILE"
}

build_report
log "Full status report generated at $REPORT_FILE"

case "$MODE" in
  send)
    python3 "$BASE_DIR/send_status_email.py" "$MAIL_CONFIG" \
      "Full status report from {hostname}" \
      "$(cat "$REPORT_FILE")" >>"$(current_log_file)" 2>&1
    log "Full status report send step completed"
    printf 'Report saved: %s\n' "$REPORT_FILE"
    ;;
  preview)
    cat "$REPORT_FILE"
    ;;
  mailto)
    open_mailto
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
