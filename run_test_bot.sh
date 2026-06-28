#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/autostart_config.sh"

LOG_DIR="$BASE_DIR/logs"
LOG_FILE="$LOG_DIR/test_env_bot.log"
CONDA_BIN="${CONDA_BIN:-${AUTOSTART_CONDA_BIN:-}}"
if [[ -z "$CONDA_BIN" ]]; then
  CONDA_BIN="$(command -v conda || true)"
fi

mkdir -p "$LOG_DIR"

if [[ -z "$CONDA_BIN" ]]; then
  echo "conda not found. Set CONDA_BIN or install the test environment." >>"$LOG_FILE"
  exit 127
fi

exec "$CONDA_BIN" run -n test python "$BASE_DIR/test_env_bot.py" >>"$LOG_FILE" 2>&1
