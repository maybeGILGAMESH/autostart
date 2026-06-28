#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"
bash "$BASE_DIR/render_autostart_config.sh"

AUTOSTART_DIR="$HOME/.config/autostart"
TUNA_LINK="$AUTOSTART_DIR/tuna-ssh.desktop"
CRON_BEGIN="# BEGIN AUTOSTART_REBOOT"
CRON_END="# END AUTOSTART_REBOOT"
CRON_CMD="@reboot $BASE_DIR/cron_reboot.sh"

mkdir -p "$AUTOSTART_DIR"
chmod +x \
  "$BASE_DIR/autostart_tuna.sh" \
  "$BASE_DIR/send_boot_report.py" \
  "$BASE_DIR/send_status_email.py" \
  "$BASE_DIR/telegram_get_chat_id.py" \
  "$BASE_DIR/log_helpers.sh" \
  "$BASE_DIR/autostart_config.sh" \
  "$BASE_DIR/render_autostart_config.sh" \
  "$BASE_DIR/install_autostart.sh" \
  "$BASE_DIR/install_systemd_fallback.sh" \
  "$BASE_DIR/tuna_interactive.sh" \
  "$BASE_DIR/tuna_headless.sh" \
  "$BASE_DIR/vnc_keepalive.sh" \
  "$BASE_DIR/cron_reboot.sh" \
  "$BASE_DIR/fallback_orchestrator.sh" \
  "$BASE_DIR/health_check.sh" \
  "$BASE_DIR/toggle_auto_reboot.sh" \
  "$BASE_DIR/stop_all.sh" \
  "$BASE_DIR/run_test_bot.sh" \
  "$BASE_DIR/debug_run.sh" \
  "$BASE_DIR/send_full_status_report.sh" \
  "$BASE_DIR/test_env_bot.py" \
  "$BASE_DIR/install_full_autonomy.sh" \
  "$BASE_DIR/status_all.sh"

# удаляем старые записи автозапуска vpn-клиентов, если они уже были установлены
rm -f \
  "$AUTOSTART_DIR/hiddify-client.desktop" \
  "$AUTOSTART_DIR/hiddify.desktop" \
  "$AUTOSTART_DIR/Hiddify.desktop" \
  "$AUTOSTART_DIR/outline-client.desktop" \
  "$AUTOSTART_DIR/outline.desktop" \
  "$AUTOSTART_DIR/Outline.desktop" \
  "$AUTOSTART_DIR/org.getoutline.OutlineClient.desktop" \
  "$AUTOSTART_DIR/org.getoutline.Outline.desktop"

ln -sfn "$BASE_DIR/tuna-ssh.desktop" "$TUNA_LINK"

existing_cron="$(crontab -l 2>/dev/null || true)"
filtered_cron="$(printf '%s\n' "$existing_cron" | awk -v begin="$CRON_BEGIN" -v end="$CRON_END" '
  $0 == begin {skip=1; next}
  $0 == end {skip=0; next}
  !skip {print}
')"

{
  printf '%s\n' "$filtered_cron"
  printf '%s\n' "$CRON_BEGIN"
  printf '%s\n' "$CRON_CMD"
  printf '%s\n' "$CRON_END"
} | awk 'NF || !blank {print; blank = ($0 == "")}' | crontab -

printf 'Autostart enabled: %s -> %s\n' "$TUNA_LINK" "$BASE_DIR/tuna-ssh.desktop"
printf 'VPN autostart removed: Hiddify and Outline desktop entries are not installed\n'
printf 'Crontab installed: %s\n' "$CRON_CMD"
