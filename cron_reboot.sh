#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if ! pgrep -af '[t]una (ssh|tcp)' >/dev/null 2>&1; then
  nohup "$BASE_DIR/tuna_headless.sh" >>"$LOG_DIR/cron_tuna_headless.log" 2>&1 &
fi

exec "$BASE_DIR/vnc_keepalive.sh" >>"$LOG_DIR/cron_reboot.log" 2>&1
