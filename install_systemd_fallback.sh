#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="$BASE_DIR/systemd"

bash "$BASE_DIR/render_autostart_config.sh"

for file in \
  autostart-vnc-keepalive.service \
  autostart-fallback.service \
  autostart-test-bot.service \
  autostart-tuna-backup.service \
  autostart-healthcheck.service \
  autostart-healthcheck.timer \
  autostart-periodic-status.service \
  autostart-periodic-status.timer
do
  install -m 0644 "$SYSTEMD_DIR/$file" "/etc/systemd/system/$file"
done

systemctl daemon-reload
systemctl enable --now autostart-vnc-keepalive.service
systemctl enable --now autostart-fallback.service
systemctl enable --now autostart-test-bot.service
systemctl enable --now autostart-tuna-backup.service
systemctl enable --now autostart-healthcheck.timer
systemctl enable --now autostart-periodic-status.timer
