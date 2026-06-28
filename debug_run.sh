#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$BASE_DIR/logs"
STATE_DIR="$BASE_DIR/generated"
MODE="${1:-live}"

mkdir -p "$LOG_DIR" "$STATE_DIR"

usage() {
  cat <<'EOF'
Usage:
  debug_run.sh live
  debug_run.sh safe
  debug_run.sh status

Modes:
  live    Run a real local test: rerun Hiddify autostart logic, then launch tuna autostart.
  safe    Same as live, but force-disable email sending.
  status  Show current stack status and recent logs.
EOF
}

reset_boot_markers() {
  rm -f \
    "$STATE_DIR/tuna_terminal.boot_id" \
    "$STATE_DIR/hiddify_autostart.boot_id"
}

show_status() {
  "$BASE_DIR/status_all.sh"
  printf '\nRecent logs:\n'
  printf '\n[autostart.log]\n'
  tail -n 20 "$LOG_DIR/autostart.log" 2>/dev/null || true
  printf '\n[hiddify_autostart.log]\n'
  tail -n 20 "$LOG_DIR/hiddify_autostart.log" 2>/dev/null || true
  printf '\n[tuna_headless.log]\n'
  tail -n 20 "$LOG_DIR/tuna_headless.log" 2>/dev/null || true
}

run_live() {
  local skip_email="${1:-0}"

  reset_boot_markers

  printf 'Running Hiddify autostart test...\n'
  HIDDIFY_SKIP_AUTOSTART=0 "$BASE_DIR/hiddify_autostart.sh" &
  local hiddify_pid=$!

  printf 'Waiting 3 seconds before tuna launch...\n'
  sleep 3

  printf 'Running tuna autostart test...\n'
  AUTOSTART_SKIP_EMAIL="$skip_email" AUTOSTART_SKIP_TERMINAL=0 "$BASE_DIR/autostart_tuna.sh"

  wait "$hiddify_pid" || true

  printf '\nTest run finished. Current status:\n\n'
  show_status
}

case "$MODE" in
  live)
    run_live 0
    ;;
  safe)
    run_live 1
    ;;
  status)
    show_status
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
