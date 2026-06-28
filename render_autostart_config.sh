#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

render_template() {
  local template="$1"
  local output="$2"
  sed \
    -e "s|{{AUTOSTART_USER}}|$AUTOSTART_USER|g" \
    -e "s|{{AUTOSTART_GROUP}}|$AUTOSTART_GROUP|g" \
    -e "s|{{AUTOSTART_HOME}}|$AUTOSTART_HOME|g" \
    -e "s|{{AUTOSTART_DIR}}|$AUTOSTART_DIR|g" \
    -e "s|{{AUTOSTART_UID}}|$AUTOSTART_UID|g" \
    -e "s|{{AUTOSTART_XAUTHORITY}}|$AUTOSTART_XAUTHORITY|g" \
    -e "s|{{AUTOSTART_XDG_RUNTIME_DIR}}|$AUTOSTART_XDG_RUNTIME_DIR|g" \
    -e "s|{{AUTOSTART_DBUS_SESSION_BUS_ADDRESS}}|$AUTOSTART_DBUS_SESSION_BUS_ADDRESS|g" \
    "$template" >"$output"
}

for template in "$BASE_DIR"/systemd/*.template; do
  [[ -f "$template" ]] || continue
  render_template "$template" "${template%.template}"
done

render_template "$BASE_DIR/tuna-ssh.desktop.template" "$BASE_DIR/tuna-ssh.desktop"

if [[ -f "$BASE_DIR/hiddify_config.env" ]]; then
  tmp_file="$(mktemp)"
  awk -v appimage="$AUTOSTART_HIDDIFY_APPIMAGE" '
    BEGIN {done=0}
    /^HIDDIFY_APPIMAGE=/ {
      print "HIDDIFY_APPIMAGE=" appimage
      done=1
      next
    }
    {print}
    END {
      if (!done) print "HIDDIFY_APPIMAGE=" appimage
    }
  ' "$BASE_DIR/hiddify_config.env" >"$tmp_file"
  mv "$tmp_file" "$BASE_DIR/hiddify_config.env"
fi

if [[ -f "$BASE_DIR/health_config.env" ]]; then
  tmp_file="$(mktemp)"
  awk -v heartbeat="$AUTOSTART_DIR/generated/test_env_bot.heartbeat" '
    BEGIN {done=0}
    /^BOT_HEARTBEAT_FILE=/ {
      print "BOT_HEARTBEAT_FILE=" heartbeat
      done=1
      next
    }
    {print}
    END {
      if (!done) print "BOT_HEARTBEAT_FILE=" heartbeat
    }
  ' "$BASE_DIR/health_config.env" >"$tmp_file"
  mv "$tmp_file" "$BASE_DIR/health_config.env"
fi

printf 'Rendered autostart config for user=%s home=%s dir=%s uid=%s\n' \
  "$AUTOSTART_USER" "$AUTOSTART_HOME" "$AUTOSTART_DIR" "$AUTOSTART_UID"
