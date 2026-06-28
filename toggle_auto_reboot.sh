#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$BASE_DIR/health_config.env"
mode="${1:-}"

if [[ "$mode" != "on" && "$mode" != "off" ]]; then
  printf 'Usage: %s on|off\n' "$0" >&2
  exit 2
fi

python3 - "$CONFIG_FILE" "$mode" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
value = "1" if mode == "on" else "0"

lines = path.read_text(encoding="utf-8").splitlines()
updated = []
changed = False
for line in lines:
    if line.startswith("AUTO_REBOOT_ENABLED="):
        updated.append(f"AUTO_REBOOT_ENABLED={value}")
        changed = True
    else:
        updated.append(line)

if not changed:
    updated.append(f"AUTO_REBOOT_ENABLED={value}")

path.write_text("\n".join(updated) + "\n", encoding="utf-8")
print(f"AUTO_REBOOT_ENABLED={value}")
PY
