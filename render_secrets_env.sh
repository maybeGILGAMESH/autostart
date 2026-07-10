#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SECRETS_FILE:-$BASE_DIR/secrets.env}"

if [[ ! -f "$SECRETS_FILE" ]]; then
  printf 'Secrets file not found: %s\n' "$SECRETS_FILE" >&2
  printf 'Create it with: cp secrets.env.example secrets.env\n' >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$SECRETS_FILE"
set +a

write_telegram_config() {
  cat >"$BASE_DIR/telegram_config.env" <<EOF
TELEGRAM_ENABLED=${TELEGRAM_ENABLED:-0}
TG_BOT_TOKEN=${TG_BOT_TOKEN:-}
TG_CHAT_ID=${TG_CHAT_ID:-}
TELEGRAM_PROXY_URL=${TELEGRAM_PROXY_URL:-http://127.0.0.1:12334}
TELEGRAM_TIMEOUT_SECONDS=${TELEGRAM_TIMEOUT_SECONDS:-12}
EOF
  chmod 600 "$BASE_DIR/telegram_config.env"
}

write_mail_config() {
  cat >"$BASE_DIR/mail_config.env" <<EOF
MAIL_ENABLED=${MAIL_ENABLED:-0}
SMTP_HOST=${SMTP_HOST:-}
SMTP_PORT=${SMTP_PORT:-465}
SMTP_SSL=${SMTP_SSL:-1}
SMTP_USER=${SMTP_USER:-}
SMTP_PASSWORD=${SMTP_PASSWORD:-}
MAIL_FROM=${MAIL_FROM:-}
MAIL_TO=${MAIL_TO:-}
SMTP_TIMEOUT_SECONDS=${SMTP_TIMEOUT_SECONDS:-12}
EOF
  chmod 600 "$BASE_DIR/mail_config.env"
}

write_tuna_config() {
  cat >"$BASE_DIR/tuna_config.env" <<EOF
TUNA_TUNNEL_MODE=${TUNA_TUNNEL_MODE:-tcp}
TUNA_TCP_TARGET=${TUNA_TCP_TARGET:-22}
# Optional: set this if access reports must include a literal password in tcp mode.
TUNA_ACCESS_PASSWORD=${TUNA_ACCESS_PASSWORD:-}
TUNA_WAIT_FOR_PROXY_SECONDS=${TUNA_WAIT_FOR_PROXY_SECONDS:-180}
TUNA_RESTART_DELAY_SECONDS=${TUNA_RESTART_DELAY_SECONDS:-5}
MAIL_SEND_RETRIES=${MAIL_SEND_RETRIES:-8}
MAIL_SEND_RETRY_DELAY_SECONDS=${MAIL_SEND_RETRY_DELAY_SECONDS:-30}
TUNA_ACCESS_NOTIFY_ENABLED=${TUNA_ACCESS_NOTIFY_ENABLED:-1}
EOF
  chmod 600 "$BASE_DIR/tuna_config.env"
}

write_telegram_config
write_mail_config
write_tuna_config

printf 'Rendered telegram_config.env, mail_config.env, tuna_config.env from %s\n' "$SECRETS_FILE"
