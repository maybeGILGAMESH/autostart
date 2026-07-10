#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/app"
WORKSPACE="${WORKSPACE:-/workspace}"
COMMAND="${1:-help}"

target_dir() {
  if [[ -d "$WORKSPACE" && -f "$WORKSPACE/render_autostart_config.sh" ]]; then
    printf '%s\n' "$WORKSPACE"
  else
    printf '%s\n' "$APP_DIR"
  fi
}

run_validate() {
  local dir="$1"
  cd "$dir"
  bash -n \
    autostart_config.sh \
    render_autostart_config.sh \
    render_secrets_env.sh \
    autostart_tuna.sh \
    cron_reboot.sh \
    debug_run.sh \
    env_helpers.sh \
    fallback_orchestrator.sh \
    health_check.sh \
    hiddify_autostart.sh \
    install_autostart.sh \
    install_full_autonomy.sh \
    install_systemd_fallback.sh \
    log_helpers.sh \
    periodic_status.sh \
    refresh_tuna_access.sh \
    run_test_bot.sh \
    send_full_status_report.sh \
    status_all.sh \
    stop_all.sh \
    toggle_auto_reboot.sh \
    tuna_headless.sh \
    tuna_interactive.sh \
    vnc_keepalive.sh

  python3 -m py_compile \
    capture_tuna_access.py \
    send_boot_report.py \
    send_status_email.py \
    telegram_get_chat_id.py \
    test_env_bot.py

  if [[ -d tests ]]; then
    python3 -m unittest discover -s tests
  fi
}

run_render() {
  local dir="$1"
  cd "$dir"
  bash render_autostart_config.sh
  if [[ -f secrets.env ]]; then
    bash render_secrets_env.sh
  else
    printf 'secrets.env not found; skipped secret rendering. Create it from secrets.env.example.\n' >&2
  fi
  fix_workspace_ownership "$dir"
}

run_export() {
  local dir="$1"
  cd "$dir"
  run_render "$dir"
  printf 'Project prepared at %s. Run host installation on the host, not inside Docker:\n' "$dir"
  printf '  conda env update -f environment.yml --prune\n'
  printf '  ./install_full_autonomy.sh\n'
}

show_help() {
  cat <<'EOF'
Usage:
  docker run --rm -v "$PWD:/workspace" autostart-stack validate
  docker run --rm --env-file ./secrets.env -v "$PWD:/workspace" autostart-stack render
  docker run --rm --env-file ./secrets.env -v "$PWD:/workspace" autostart-stack export

Commands:
  validate  Run shell syntax checks, Python compile, and unit tests.
  render    Render systemd/desktop config from autostart_config.env and runtime secrets from secrets.env.
  export    Render files and print host installation next steps.
  help      Show this help.

This image is a host-installer/helper image. It does not run host systemd,
VNC, GNOME terminal, Hiddify GUI, or the persistent tuna tunnel inside Docker.
EOF
}

fix_workspace_ownership() {
  local dir="$1"
  local uid gid
  uid="$(stat -c '%u' "$dir" 2>/dev/null || true)"
  gid="$(stat -c '%g' "$dir" 2>/dev/null || true)"
  if [[ -n "$uid" && -n "$gid" && "$uid" != "0" ]]; then
    chown "$uid:$gid" \
      "$dir"/telegram_config.env \
      "$dir"/mail_config.env \
      "$dir"/tuna_config.env \
      "$dir"/hiddify_config.env \
      "$dir"/health_config.env \
      "$dir"/tuna-ssh.desktop \
      "$dir"/systemd/*.service \
      2>/dev/null || true
  fi
}

main() {
  local dir
  dir="$(target_dir)"
  case "$COMMAND" in
    validate)
      run_validate "$dir"
      ;;
    render)
      run_render "$dir"
      ;;
    export)
      run_export "$dir"
      ;;
    help|--help|-h)
      show_help
      ;;
    *)
      printf 'Unknown command: %s\n\n' "$COMMAND" >&2
      show_help >&2
      exit 2
      ;;
  esac
}

main "$@"
