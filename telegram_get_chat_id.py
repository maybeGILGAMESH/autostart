#!/usr/bin/env python3
import json
import os
import sys
import urllib.request
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = Path(os.environ.get("TELEGRAM_CONFIG_PATH", BASE_DIR / "telegram_config.env"))


def load_config() -> dict[str, str]:
    data: dict[str, str] = {}
    for raw_line in CONFIG_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def save_chat_id(chat_id: str) -> None:
    lines = CONFIG_PATH.read_text(encoding="utf-8").splitlines()
    updated: list[str] = []
    changed = False
    for line in lines:
        if line.startswith("TG_CHAT_ID="):
            updated.append(f"TG_CHAT_ID={chat_id}")
            changed = True
        else:
            updated.append(line)
    if not changed:
        updated.append(f"TG_CHAT_ID={chat_id}")
    CONFIG_PATH.write_text("\n".join(updated) + "\n", encoding="utf-8")


def main() -> int:
    config = load_config()
    token = config.get("TG_BOT_TOKEN", "")
    if not token:
        print("TG_BOT_TOKEN is empty", file=sys.stderr)
        return 1

    url = f"https://api.telegram.org/bot{token}/getUpdates"
    with urllib.request.urlopen(url, timeout=20) as response:
        data = json.load(response)

    if not data.get("ok"):
        print("Telegram API returned ok=false", file=sys.stderr)
        return 1

    results = data.get("result", [])
    chat_ids: list[str] = []
    for item in results:
        msg = (
            item.get("message")
            or item.get("edited_message")
            or item.get("channel_post")
            or item.get("my_chat_member")
            or {}
        )
        chat = msg.get("chat") or {}
        chat_id = chat.get("id")
        if chat_id is not None:
            text = str(chat_id)
            if text not in chat_ids:
                chat_ids.append(text)

    if not chat_ids:
        print("No chat_id found. Send any message to the bot first, then run this command again.")
        return 2

    selected = chat_ids[-1]
    save_chat_id(selected)
    print(f"Saved TG_CHAT_ID={selected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
