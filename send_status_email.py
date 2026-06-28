#!/usr/bin/env python3
import socket
import ssl
import smtplib
import sys
import time
import urllib.parse
import urllib.request
from email.message import EmailMessage
from pathlib import Path
from urllib.error import HTTPError, URLError

TELEGRAM_TEXT_LIMIT = 4000
TELEGRAM_SEND_RETRIES = 6
TELEGRAM_RETRY_DELAY_SECONDS = 15
TELEGRAM_TIMEOUT_SECONDS = 12
MAIL_SEND_RETRIES = 4
MAIL_RETRY_DELAY_SECONDS = 20
SMTP_TIMEOUT_SECONDS = 12
DEFAULT_TELEGRAM_PROXY_URL = "http://127.0.0.1:12334"


def load_env(path: str) -> dict[str, str]:
    data: dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def to_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on"}


def send_email(config: dict[str, str], subject: str, body: str) -> None:
    if not to_bool(config.get("MAIL_ENABLED", "0")):
        print("MAIL_ENABLED is disabled, skipping email")
        return

    required = [
        "SMTP_HOST",
        "SMTP_PORT",
        "SMTP_USER",
        "SMTP_PASSWORD",
        "MAIL_FROM",
        "MAIL_TO",
    ]
    missing = [key for key in required if not config.get(key)]
    if missing:
        raise RuntimeError(f"Missing required mail settings: {', '.join(missing)}")

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = config["MAIL_FROM"]
    message["To"] = config["MAIL_TO"]
    message.set_content(body)

    smtp_host = config["SMTP_HOST"]
    smtp_port = int(config["SMTP_PORT"])
    smtp_user = config["SMTP_USER"]
    smtp_password = config["SMTP_PASSWORD"]
    use_ssl = to_bool(config.get("SMTP_SSL", "1"))
    timeout = int(config.get("SMTP_TIMEOUT_SECONDS", str(SMTP_TIMEOUT_SECONDS)))

    if use_ssl:
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(smtp_host, smtp_port, context=context, timeout=timeout) as server:
            server.login(smtp_user, smtp_password)
            server.send_message(message)
    else:
        with smtplib.SMTP(smtp_host, smtp_port, timeout=timeout) as server:
            server.starttls(context=ssl.create_default_context())
            server.login(smtp_user, smtp_password)
            server.send_message(message)


def send_email_with_retries(config: dict[str, str], subject: str, body: str) -> None:
    retries = int(config.get("MAIL_SEND_RETRIES", str(MAIL_SEND_RETRIES)))
    retry_delay = int(config.get("MAIL_RETRY_DELAY_SECONDS", str(MAIL_RETRY_DELAY_SECONDS)))
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            send_email(config, subject, body)
            return
        except Exception as exc:
            last_error = exc
            if attempt >= retries:
                break
            print(f"Email send attempt {attempt} failed: {exc}", file=sys.stderr)
            time.sleep(retry_delay)
    assert last_error is not None
    raise last_error


def proxy_is_reachable(proxy_url: str) -> bool:
    parsed = urllib.parse.urlparse(proxy_url)
    if not parsed.hostname or not parsed.port:
        return False
    try:
        with socket.create_connection((parsed.hostname, parsed.port), timeout=2):
            return True
    except OSError:
        return False


def telegram_opener(config: dict[str, str]) -> urllib.request.OpenerDirector:
    proxy_url = config.get("TELEGRAM_PROXY_URL", "").strip()
    if not proxy_url:
        proxy_url = DEFAULT_TELEGRAM_PROXY_URL

    if proxy_is_reachable(proxy_url):
        return urllib.request.build_opener(
            urllib.request.ProxyHandler(
                {
                    "http": proxy_url,
                    "https": proxy_url,
                }
            )
        )

    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


def send_telegram(config: dict[str, str], subject: str, body: str) -> None:
    if not to_bool(config.get("TELEGRAM_ENABLED", "0")):
        print("TELEGRAM_ENABLED is disabled, skipping telegram")
        return

    token = config.get("TG_BOT_TOKEN", "")
    chat_id = config.get("TG_CHAT_ID", "")
    if not token or not chat_id:
        raise RuntimeError("Missing TG_BOT_TOKEN or TG_CHAT_ID")

    retries = int(config.get("TELEGRAM_SEND_RETRIES", str(TELEGRAM_SEND_RETRIES)))
    retry_delay = int(config.get("TELEGRAM_RETRY_DELAY_SECONDS", str(TELEGRAM_RETRY_DELAY_SECONDS)))
    timeout = int(config.get("TELEGRAM_TIMEOUT_SECONDS", str(TELEGRAM_TIMEOUT_SECONDS)))
    opener = telegram_opener(config)
    text = f"{subject}\n\n{body}"
    chunks = split_telegram_text(text, TELEGRAM_TEXT_LIMIT)
    total = len(chunks)
    for index, chunk in enumerate(chunks, start=1):
        chunk_text = chunk
        if total > 1:
            prefix = f"[{index}/{total}] "
            chunk_text = prefix + chunk
        payload = urllib.parse.urlencode(
            {
                "chat_id": chat_id,
                "text": chunk_text,
                "disable_web_page_preview": "true",
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=payload,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            method="POST",
        )
        attempt = 1
        while True:
            try:
                with opener.open(request, timeout=timeout) as response:
                    response.read()
                break
            except HTTPError:
                raise
            except URLError:
                if attempt >= retries:
                    raise
                time.sleep(retry_delay)
                attempt += 1


def split_telegram_text(text: str, limit: int) -> list[str]:
    if len(text) <= limit:
        return [text]

    chunks: list[str] = []
    remaining = text
    while len(remaining) > limit:
        split_at = remaining.rfind("\n", 0, limit)
        if split_at <= 0:
            split_at = remaining.rfind(" ", 0, limit)
        if split_at <= 0:
            split_at = limit
        chunks.append(remaining[:split_at].rstrip())
        remaining = remaining[split_at:].lstrip()
    if remaining:
        chunks.append(remaining)
    return chunks


def main() -> int:
    if len(sys.argv) < 4:
        print("Usage: send_status_email.py MAIL_CONFIG SUBJECT BODY...", file=sys.stderr)
        return 2

    config_path = sys.argv[1]
    subject = sys.argv[2]
    body = " ".join(sys.argv[3:])

    if "{hostname}" in subject or "{hostname}" in body:
        hostname = socket.gethostname()
        subject = subject.replace("{hostname}", hostname)
        body = body.replace("{hostname}", hostname)

    config = load_env(config_path)
    telegram_path = Path(config_path).with_name("telegram_config.env")
    enabled_channels = 0
    successful_channels = 0

    if telegram_path.exists():
        telegram_config = load_env(str(telegram_path))
        if to_bool(telegram_config.get("TELEGRAM_ENABLED", "0")):
            enabled_channels += 1
            try:
                send_telegram(telegram_config, subject, body)
                print("Telegram notification sent")
                successful_channels += 1
            except Exception as exc:
                print(f"Telegram send failed: {exc}", file=sys.stderr)
        else:
            print("TELEGRAM_ENABLED is disabled, skipping telegram")
    else:
        print("telegram_config.env is missing, skipping telegram")

    if to_bool(config.get("MAIL_ENABLED", "0")):
        enabled_channels += 1
        try:
            send_email_with_retries(config, subject, body)
            print(f"Email sent to {config.get('MAIL_TO', '')}")
            successful_channels += 1
        except Exception as exc:
            print(f"Email send failed: {exc}", file=sys.stderr)
    else:
        print("MAIL_ENABLED is disabled, skipping email")

    print("Notification step completed")
    if enabled_channels == 0 or successful_channels > 0:
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
