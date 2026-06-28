#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$BASE_DIR/install_autostart.sh"
sudo "$BASE_DIR/install_systemd_fallback.sh"
