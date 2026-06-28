#!/usr/bin/env bash
set -euo pipefail

init_hourly_logging() {
  local log_basename="$1"
  LOG_BASENAME="$log_basename"
  LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
  mkdir -p "$LOG_DIR"
}

current_log_file() {
  local log_file="$LOG_DIR/${LOG_BASENAME}_$(date +%Y%m%d_%H).log"
  ln -sfn "$(basename "$log_file")" "$LOG_DIR/${LOG_BASENAME}.log"
  printf '%s\n' "$log_file"
}

log() {
  local log_file
  log_file="$(current_log_file)"
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*" | tee -a "$log_file" >/dev/null
}
