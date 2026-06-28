#!/usr/bin/env python3
import smtplib
import socket
import ssl
import sys
from email.message import EmailMessage


def load_env(path: str) -> dict[str, str]:
    data: dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            data[key] = value
    return data


def to_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on"}


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: send_boot_report.py REPORT_FILE MAIL_CONFIG", file=sys.stderr)
        return 2

    report_path, config_path = sys.argv[1], sys.argv[2]
    config = load_env(config_path)

    if not to_bool(config.get("MAIL_ENABLED", "0")):
        print("MAIL_ENABLED is disabled, skipping email")
        return 0

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
        print(f"Missing required mail settings: {', '.join(missing)}", file=sys.stderr)
        return 1

    with open(report_path, "r", encoding="utf-8") as handle:
        report_text = handle.read()

    hostname = socket.gethostname()
    subject = f"Boot report from {hostname}"

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = config["MAIL_FROM"]
    message["To"] = config["MAIL_TO"]
    message.set_content(report_text)

    smtp_host = config["SMTP_HOST"]
    smtp_port = int(config["SMTP_PORT"])
    smtp_user = config["SMTP_USER"]
    smtp_password = config["SMTP_PASSWORD"]
    use_ssl = to_bool(config.get("SMTP_SSL", "1"))

    if use_ssl:
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(smtp_host, smtp_port, context=context, timeout=30) as server:
            server.login(smtp_user, smtp_password)
            server.send_message(message)
    else:
        with smtplib.SMTP(smtp_host, smtp_port, timeout=30) as server:
            server.starttls(context=ssl.create_default_context())
            server.login(smtp_user, smtp_password)
            server.send_message(message)

    print(f"Email sent to {config['MAIL_TO']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
