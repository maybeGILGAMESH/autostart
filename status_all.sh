#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

printf 'VNC process:\n'
ps -ef | grep '[X]tigervnc' || true
printf '\nVNC port:\n'
ss -ltnp | grep 5901 || true
printf '\nHiddify process:\n'
ps -ef | grep -i '[h]iddify' || true
printf '\nHiddify port:\n'
ss -ltnp | grep 12334 || true
printf '\nTuna process:\n'
ps -ef | grep '[t]una ' || true
printf '\nTuna ssh process:\n'
ps -ef | grep '[t]una ssh' || true
printf '\nTuna tcp process:\n'
ps -ef | grep '[t]una tcp' || true
printf '\nTuna http process:\n'
ps -ef | grep '[t]una http' || true
printf '\nTuna listening ports:\n'
ss -ltnp 2>/dev/null | grep -i 'users:(("tuna"' || true
printf '\nLatest tuna access:\n'
sed 's/^/  /' "$AUTOSTART_DIR/generated/tuna_access_latest.txt" 2>/dev/null || echo '  not captured yet'
printf '\nLast tuna service logs:\n'
journalctl --user -u autostart-tuna-backup.service -n 10 --no-pager 2>/dev/null || true
printf '\nSystemd services:\n'
systemctl is-active autostart-vnc-keepalive.service 2>/dev/null || true
systemctl is-active autostart-fallback.service 2>/dev/null || true
systemctl is-active autostart-test-bot.service 2>/dev/null || true
systemctl is-active autostart-tuna-backup.service 2>/dev/null || true
systemctl is-active autostart-healthcheck.timer 2>/dev/null || true
systemctl is-active autostart-periodic-status.timer 2>/dev/null || true
