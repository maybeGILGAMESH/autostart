#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

LOG_DIR="$BASE_DIR/logs"

mkdir -p "$LOG_DIR"

# shellcheck disable=SC1091
source "$BASE_DIR/log_helpers.sh"
init_hourly_logging "periodic_status"

log "Periodic status send started"
if "$AUTOSTART_DIR/send_full_status_report.sh" send >>"$(current_log_file)" 2>&1; then
  log "Periodic status send completed"
else
  log "Periodic status send failed, see nested logs for details"
fi
