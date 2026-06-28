#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

printf 'Stopping user autostart processes...\n'
pkill -f '/usr/bin/tuna ssh' 2>/dev/null || true
pkill -f '/usr/bin/tuna --no-colors ssh' 2>/dev/null || true
pkill -f '/usr/bin/tuna tcp' 2>/dev/null || true
pkill -f '/usr/bin/tuna --no-colors tcp' 2>/dev/null || true
pkill -f 'Hiddify-Linux-x64.AppImage' 2>/dev/null || true
pkill -f "$AUTOSTART_DIR/test_env_bot.py" 2>/dev/null || true
pkill -f '/usr/bin/Xtigervnc :1' 2>/dev/null || true

printf 'Stopping systemd services...\n'
sudo systemctl stop \
  autostart-healthcheck.timer \
  autostart-tuna-backup.service \
  autostart-test-bot.service \
  autostart-fallback.service \
  autostart-vnc-keepalive.service || true

printf 'Stopping VNC session...\n'
/usr/bin/vncserver -kill :1 2>/dev/null || true

printf 'Current status:\n\n'
"$BASE_DIR/status_all.sh" || true
