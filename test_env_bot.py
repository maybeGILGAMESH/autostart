#!/usr/bin/env python3
import pathlib
import subprocess
import socket
import sys
import time
import urllib.parse
import urllib.request
import json
import re
from urllib.error import HTTPError, URLError


BASE_DIR = pathlib.Path(__file__).resolve().parent
STATE_DIR = BASE_DIR / "generated"
LOG_DIR = BASE_DIR / "logs"
MAIL_CONFIG = BASE_DIR / "mail_config.env"
TELEGRAM_CONFIG = BASE_DIR / "telegram_config.env"
BOT_CONFIG = BASE_DIR / "test_bot.env"
HEARTBEAT_FILE = STATE_DIR / "test_env_bot.heartbeat"
START_SENT_FILE = STATE_DIR / "test_env_bot.startup_sent"
TELEGRAM_OFFSET_FILE = STATE_DIR / "test_env_bot.telegram_offset"
MACHINE_ALIASES_FILE = STATE_DIR / "test_env_bot.machine_aliases.json"
TELEGRAM_HELD_UPDATES_FILE = STATE_DIR / "test_env_bot.held_updates.json"
TELEGRAM_BACKOFF_NOTIFIED_FILE = STATE_DIR / "test_env_bot.backoff_notified.json"
TUNA_ACCESS_FILE = STATE_DIR / "tuna_access_latest.txt"
REFRESH_TUNA_ACCESS = BASE_DIR / "refresh_tuna_access.sh"
BOOT_ID_FILE = pathlib.Path("/proc/sys/kernel/random/boot_id")
DEFAULT_TELEGRAM_PROXY_URL = "http://127.0.0.1:12334"
DEFAULT_TELEGRAM_POLL_TIMEOUT_SECONDS = 25
DEFAULT_TELEGRAM_POLL_INTERVAL_SECONDS = 2
DEFAULT_UPDATE_COMMAND_TIMEOUT_SECONDS = 150
DEFAULT_FOREIGN_COMMAND_BACKOFF_SECONDS = 30
DEFAULT_INVALID_TARGET_ACK_SECONDS = 45
DEFAULT_BACKOFF_NOTIFY_ENABLED = True
STARTUP_NOTIFICATION_TIMEOUT_SECONDS = 30
MACHINE_NAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def load_env(path: pathlib.Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def log(message: str) -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    runtime_log = LOG_DIR / f"test_env_bot_runtime_{time.strftime('%Y%m%d_%H')}.log"
    latest_link = LOG_DIR / "test_env_bot_runtime.log"
    try:
        if latest_link.exists() or latest_link.is_symlink():
            latest_link.unlink()
        latest_link.symlink_to(runtime_log.name)
    except OSError:
        pass
    with runtime_log.open("a", encoding="utf-8") as handle:
        handle.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {message}\n")


def send_status_email(subject: str, body: str) -> None:
    if not MAIL_CONFIG.exists():
        log("mail_config.env is missing, skipping startup message")
        return
    try:
        subprocess.run(
            [
                sys.executable,
                str(BASE_DIR / "send_status_email.py"),
                str(MAIL_CONFIG),
                subject,
                body,
            ],
            check=False,
            timeout=STARTUP_NOTIFICATION_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        log(f"startup notification timed out after {STARTUP_NOTIFICATION_TIMEOUT_SECONDS}s")


def to_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    items: list[str] = []
    seen: set[str] = set()
    for raw_item in value.split(","):
        item = raw_item.strip()
        key = item.lower()
        if item and key not in seen:
            items.append(item)
            seen.add(key)
    return items


def valid_machine_name(name: str) -> bool:
    return bool(MACHINE_NAME_RE.fullmatch(name))


def load_json_list(path: pathlib.Path) -> list[str]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(data, list):
        return []
    return [str(item).strip() for item in data if str(item).strip()]


def load_json_dict(path: pathlib.Path) -> dict[str, float]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(data, dict):
        return {}
    result: dict[str, float] = {}
    for key, value in data.items():
        try:
            result[str(key)] = float(value)
        except (TypeError, ValueError):
            continue
    return result


def save_json_dict(path: pathlib.Path, data: dict[str, float]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def save_json_list(path: pathlib.Path, items: list[str]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def unique_names(items: list[str]) -> list[str]:
    names: list[str] = []
    seen: set[str] = set()
    for item in items:
        item = item.strip()
        key = item.lower()
        if item and key not in seen:
            names.append(item)
            seen.add(key)
    return names


def machine_name(config: dict[str, str]) -> str:
    configured = config.get("BOT_MACHINE_NAME", "").strip()
    if configured:
        return configured
    return socket.gethostname()


def machine_aliases(config: dict[str, str]) -> list[str]:
    hostname = socket.gethostname()
    configured_name = machine_name(config)
    configured_aliases = split_csv(config.get("BOT_MACHINE_ALIASES"))
    saved_aliases = load_json_list(MACHINE_ALIASES_FILE)
    return unique_names([configured_name, hostname, *configured_aliases, *saved_aliases])


def known_machines(config: dict[str, str]) -> list[str]:
    return unique_names([*split_csv(config.get("BOT_KNOWN_MACHINES")), *machine_aliases(config)])


def machine_is_known(config: dict[str, str], target: str) -> bool:
    target_key = target.strip().lower()
    return any(name.lower() == target_key for name in known_machines(config))


def machine_matches(config: dict[str, str], target: str) -> bool:
    target_key = target.strip().lower()
    return any(alias.lower() == target_key for alias in machine_aliases(config))


def machine_label(config: dict[str, str]) -> str:
    name = machine_name(config)
    hostname = socket.gethostname()
    if name == hostname:
        return name
    return f"{name} ({hostname})"


def parse_bot_command(text: str) -> tuple[str, str, list[str]]:
    parts = text.split()
    if not parts:
        return "", "", []
    command = parts[0].lower().lstrip("/")
    command = command.split("@", 1)[0]
    target = parts[1].strip() if len(parts) > 1 else ""
    args = parts[2:] if len(parts) > 2 else []
    return command, target, args


def held_update_age(update_id: int) -> float:
    now = time.time()
    key = str(update_id)
    held_updates = load_json_dict(TELEGRAM_HELD_UPDATES_FILE)
    first_seen = held_updates.get(key)
    if first_seen is None:
        held_updates[key] = now
        save_json_dict(TELEGRAM_HELD_UPDATES_FILE, held_updates)
        return 0.0
    return max(0.0, now - first_seen)


def forget_held_update(update_id: int) -> None:
    key = str(update_id)
    held_updates = load_json_dict(TELEGRAM_HELD_UPDATES_FILE)
    if key in held_updates:
        held_updates.pop(key, None)
        save_json_dict(TELEGRAM_HELD_UPDATES_FILE, held_updates)
    notified_updates = load_json_list(TELEGRAM_BACKOFF_NOTIFIED_FILE)
    updated_notified = [item for item in notified_updates if item != key]
    if len(updated_notified) != len(notified_updates):
        save_json_list(TELEGRAM_BACKOFF_NOTIFIED_FILE, updated_notified)


def mark_backoff_notified(update_id: int) -> bool:
    key = str(update_id)
    notified_updates = load_json_list(TELEGRAM_BACKOFF_NOTIFIED_FILE)
    if key in notified_updates:
        return False
    save_json_list(TELEGRAM_BACKOFF_NOTIFIED_FILE, unique_names([*notified_updates, key]))
    return True


def notify_command_backoff(
    bot_config: dict[str, str],
    update_id: int,
    target: str,
    seconds: int,
    reason: str,
) -> None:
    if not to_bool(bot_config.get("BOT_BACKOFF_NOTIFY_ENABLED"), DEFAULT_BACKOFF_NOTIFY_ENABLED):
        return
    if not mark_backoff_notified(update_id):
        return

    label = machine_label(bot_config)
    subject = f"Telegram polling paused on {label}"
    body = (
        f"Machine: {label}\n"
        f"Update id: {update_id}\n"
        f"Target machine: {target}\n"
        f"Reason: {reason}\n"
        f"Sleep seconds: {seconds}\n\n"
        "Only Telegram getUpdates polling is paused. The autostart stack and the bot process keep running.\n"
        "The Telegram offset was not advanced, so the target machine can still receive this command."
    )
    send_status_email(subject, body)


def sleep_for_command_backoff(
    bot_config: dict[str, str],
    update_id: int,
    target: str,
    reason: str = "command is addressed to another machine",
) -> None:
    seconds = int(
        bot_config.get(
            "BOT_FOREIGN_COMMAND_BACKOFF_SECONDS",
            str(DEFAULT_FOREIGN_COMMAND_BACKOFF_SECONDS),
        )
    )
    held_update_age(update_id)
    log(f"update_id={update_id} is for machine={target}; sleeping {seconds}s without advancing offset")
    notify_command_backoff(bot_config, update_id, target, seconds, reason)
    time.sleep(seconds)


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
    proxy_url = config.get("TELEGRAM_PROXY_URL", "").strip() or DEFAULT_TELEGRAM_PROXY_URL
    if proxy_is_reachable(proxy_url):
        return urllib.request.build_opener(
            urllib.request.ProxyHandler({"http": proxy_url, "https": proxy_url})
        )
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


def telegram_api(
    config: dict[str, str],
    method: str,
    params: dict[str, str | int],
    timeout: int,
) -> dict:
    token = config.get("TG_BOT_TOKEN", "").strip()
    if not token:
        raise RuntimeError("TG_BOT_TOKEN is missing")

    payload = urllib.parse.urlencode(params).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/{method}",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with telegram_opener(config).open(request, timeout=timeout) as response:
        data = json.loads(response.read().decode("utf-8"))
    if not data.get("ok"):
        raise RuntimeError(f"Telegram API {method} failed: {data}")
    return data


def send_telegram_reply(
    config: dict[str, str],
    chat_id: str,
    text: str,
    reply_to_message_id: int | None = None,
) -> None:
    timeout = int(config.get("TELEGRAM_TIMEOUT_SECONDS", "12"))
    params: dict[str, str | int] = {
        "chat_id": chat_id,
        "text": text[:3900],
        "disable_web_page_preview": "true",
    }
    if reply_to_message_id is not None:
        params["reply_to_message_id"] = reply_to_message_id
    telegram_api(config, "sendMessage", params, timeout)


def load_telegram_offset() -> int:
    if not TELEGRAM_OFFSET_FILE.exists():
        return 0
    try:
        return int(TELEGRAM_OFFSET_FILE.read_text(encoding="utf-8").strip())
    except ValueError:
        return 0


def save_telegram_offset(offset: int) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    TELEGRAM_OFFSET_FILE.write_text(str(offset), encoding="utf-8")


def read_tuna_access() -> str:
    if not TUNA_ACCESS_FILE.exists():
        return "Tuna access file is not ready yet."
    return TUNA_ACCESS_FILE.read_text(encoding="utf-8").strip()


def run_update_command(config: dict[str, str]) -> tuple[int, str]:
    command = config.get("BOT_UPDATE_COMMAND", str(REFRESH_TUNA_ACCESS)).strip()
    if not command:
        return 2, "BOT_UPDATE_COMMAND is empty"
    timeout = int(config.get("BOT_UPDATE_TIMEOUT_SECONDS", str(DEFAULT_UPDATE_COMMAND_TIMEOUT_SECONDS)))
    try:
        result = subprocess.run(
            [command],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        output = "\n".join(
            part.strip()
            for part in [(exc.stdout or ""), (exc.stderr or "")]
            if part and part.strip()
        )
        return 124, output or f"Update command timed out after {timeout}s"
    except OSError as exc:
        return 127, str(exc)

    output = "\n".join(
        part.strip()
        for part in [result.stdout or "", result.stderr or ""]
        if part and part.strip()
    )
    return result.returncode, output


def handle_update_command(
    bot_config: dict[str, str],
    telegram_config: dict[str, str],
    chat_id: str,
    message_id: int | None,
) -> None:
    label = machine_label(bot_config)
    send_telegram_reply(
        telegram_config,
        chat_id,
        f"Машина: {label}\nЗапускаю обновление tuna-доступа. Сейчас перезапущу туннель и пришлю новые реквизиты.",
        message_id,
    )
    status, output = run_update_command(bot_config)
    access = read_tuna_access()
    if status == 0:
        text = f"Машина: {label}\nДоступ обновлен.\n\n{access}"
    else:
        text = f"Машина: {label}\nОбновление завершилось с ошибкой {status}.\n\n{output}\n\nПоследний сохраненный доступ:\n{access}"
    send_telegram_reply(telegram_config, chat_id, text, message_id)


def command_help(bot_config: dict[str, str]) -> str:
    machines = ", ".join(known_machines(bot_config))
    return (
        "Команды:\n"
        "update <machine> - обновить tuna-доступ выбранной машины\n"
        "status [machine] - показать последний доступ\n"
        "machines - показать известные имена машин\n"
        "addmachine <name> - добавить локальный alias для этой машины\n\n"
        f"Эта машина: {machine_label(bot_config)}\n"
        f"Известные машины: {machines}"
    )


def target_required_reply(bot_config: dict[str, str]) -> str:
    machines = ", ".join(known_machines(bot_config))
    return (
        "Укажите имя машины: update <machine>.\n"
        f"Пример: update {machine_name(bot_config)}\n"
        f"Известные машины: {machines}"
    )


def target_not_local_reply(bot_config: dict[str, str], target: str) -> str:
    aliases = ", ".join(machine_aliases(bot_config))
    return (
        f"Команда адресована машине '{target}'.\n"
        f"Эта машина: {machine_label(bot_config)}\n"
        f"Локальные имена: {aliases}"
    )


def machines_reply(bot_config: dict[str, str]) -> str:
    return (
        f"Эта машина: {machine_label(bot_config)}\n"
        f"Локальные имена: {', '.join(machine_aliases(bot_config))}\n"
        f"Известные машины: {', '.join(known_machines(bot_config))}"
    )


def add_machine_alias(bot_config: dict[str, str], name: str) -> str:
    if not valid_machine_name(name):
        return "Некорректное имя машины. Разрешены буквы, цифры, точка, дефис и подчеркивание; максимум 64 символа."

    current_aliases = load_json_list(MACHINE_ALIASES_FILE)
    updated_aliases = unique_names([*current_aliases, name])
    save_json_list(MACHINE_ALIASES_FILE, updated_aliases)
    return (
        f"Имя '{name}' добавлено как локальный alias.\n"
        f"Эта машина: {machine_label(bot_config)}\n"
        f"Локальные имена: {', '.join(machine_aliases(bot_config))}"
    )


def process_telegram_updates(bot_config: dict[str, str], telegram_config: dict[str, str]) -> None:
    if not to_bool(telegram_config.get("TELEGRAM_ENABLED"), False):
        return

    allowed_chat_id = telegram_config.get("TG_CHAT_ID", "").strip()
    if not allowed_chat_id:
        log("TG_CHAT_ID is missing, telegram commands disabled")
        return

    offset = load_telegram_offset()
    timeout = int(
        bot_config.get(
            "BOT_TELEGRAM_POLL_TIMEOUT_SECONDS",
            str(DEFAULT_TELEGRAM_POLL_TIMEOUT_SECONDS),
        )
    )

    params: dict[str, str | int] = {
        "timeout": timeout,
        "allowed_updates": json.dumps(["message"]),
    }
    if offset:
        params["offset"] = offset

    invalid_target_ack_seconds = int(
        bot_config.get(
            "BOT_INVALID_TARGET_ACK_SECONDS",
            str(DEFAULT_INVALID_TARGET_ACK_SECONDS),
        )
    )

    data = telegram_api(telegram_config, "getUpdates", params, timeout + 5)
    for update in data.get("result", []):
        update_id = int(update.get("update_id", 0))
        message = update.get("message") or {}
        chat = message.get("chat") or {}
        chat_id = str(chat.get("id", ""))
        text = (message.get("text") or "").strip()
        message_id = message.get("message_id")

        if chat_id != allowed_chat_id:
            log(f"ignored telegram command from unauthorized chat_id={chat_id}")
            forget_held_update(update_id)
            save_telegram_offset(update_id + 1)
            continue

        command, target, _args = parse_bot_command(text)
        if command == "update":
            if not target:
                send_telegram_reply(telegram_config, chat_id, target_required_reply(bot_config), message_id)
                forget_held_update(update_id)
                save_telegram_offset(update_id + 1)
                continue
            if not valid_machine_name(target):
                age = held_update_age(update_id)
                if age < invalid_target_ack_seconds:
                    sleep_for_command_backoff(bot_config, update_id, target, "invalid machine name")
                    return
                send_telegram_reply(telegram_config, chat_id, "Некорректное имя машины.", message_id)
                forget_held_update(update_id)
                save_telegram_offset(update_id + 1)
                continue
            if not machine_matches(bot_config, target):
                if machine_is_known(bot_config, target):
                    sleep_for_command_backoff(bot_config, update_id, target, "command is addressed to another known machine")
                    return
                age = held_update_age(update_id)
                if age < invalid_target_ack_seconds:
                    sleep_for_command_backoff(bot_config, update_id, target, "unknown machine name")
                    return
                send_telegram_reply(
                    telegram_config,
                    chat_id,
                    f"Неизвестная машина '{target}'.\n\n{machines_reply(bot_config)}",
                    message_id,
                )
                forget_held_update(update_id)
                save_telegram_offset(update_id + 1)
                continue
            log("received telegram update command")
            handle_update_command(bot_config, telegram_config, chat_id, message_id)
            forget_held_update(update_id)
            save_telegram_offset(update_id + 1)
        elif command in {"status", "access"}:
            if target and not valid_machine_name(target):
                age = held_update_age(update_id)
                if age < invalid_target_ack_seconds:
                    sleep_for_command_backoff(bot_config, update_id, target, "invalid machine name")
                    return
                send_telegram_reply(telegram_config, chat_id, "Некорректное имя машины.", message_id)
                forget_held_update(update_id)
                save_telegram_offset(update_id + 1)
                continue
            if target and not machine_matches(bot_config, target):
                if machine_is_known(bot_config, target):
                    sleep_for_command_backoff(bot_config, update_id, target, "command is addressed to another known machine")
                    return
                age = held_update_age(update_id)
                if age < invalid_target_ack_seconds:
                    sleep_for_command_backoff(bot_config, update_id, target, "unknown machine name")
                    return
                send_telegram_reply(
                    telegram_config,
                    chat_id,
                    f"Неизвестная машина '{target}'.\n\n{machines_reply(bot_config)}",
                    message_id,
                )
                forget_held_update(update_id)
                save_telegram_offset(update_id + 1)
                continue
            send_telegram_reply(
                telegram_config,
                chat_id,
                f"Машина: {machine_label(bot_config)}\n\n{read_tuna_access()}",
                message_id,
            )
            forget_held_update(update_id)
            save_telegram_offset(update_id + 1)
        elif command == "machines":
            send_telegram_reply(telegram_config, chat_id, machines_reply(bot_config), message_id)
            forget_held_update(update_id)
            save_telegram_offset(update_id + 1)
        elif command == "addmachine":
            if not target:
                send_telegram_reply(telegram_config, chat_id, "Использование: addmachine <name>", message_id)
                forget_held_update(update_id)
                save_telegram_offset(update_id + 1)
                continue
            send_telegram_reply(telegram_config, chat_id, add_machine_alias(bot_config, target), message_id)
            forget_held_update(update_id)
            save_telegram_offset(update_id + 1)
        elif command:
            send_telegram_reply(
                telegram_config,
                chat_id,
                command_help(bot_config),
                message_id,
            )
            forget_held_update(update_id)
            save_telegram_offset(update_id + 1)
        else:
            forget_held_update(update_id)
            save_telegram_offset(update_id + 1)


def main() -> int:
    config = load_env(BOT_CONFIG)
    telegram_config = load_env(TELEGRAM_CONFIG)
    interval = int(config.get("BOT_HEARTBEAT_INTERVAL_SECONDS", "60"))
    telegram_poll_interval = int(
        config.get(
            "BOT_TELEGRAM_POLL_INTERVAL_SECONDS",
            str(DEFAULT_TELEGRAM_POLL_INTERVAL_SECONDS),
        )
    )
    startup_message = config.get(
        "BOT_STARTUP_MESSAGE",
        "Test environment bot started on {hostname}. Python={python}.",
    )
    subject = config.get(
        "BOT_STARTUP_SUBJECT",
        "Test bot started on {hostname}",
    )

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    hostname = socket.gethostname()
    python_path = sys.executable
    boot_id = BOOT_ID_FILE.read_text(encoding="utf-8").strip() if BOOT_ID_FILE.exists() else "unknown"

    local_machine = machine_name(config)
    text = (
        startup_message
        .replace("{hostname}", hostname)
        .replace("{machine}", local_machine)
        .replace("{python}", python_path)
    )
    subject = subject.replace("{hostname}", hostname).replace("{machine}", local_machine)

    sent_boot_id = START_SENT_FILE.read_text(encoding="utf-8").strip() if START_SENT_FILE.exists() else ""
    if sent_boot_id != boot_id:
        send_status_email(subject, text)
        START_SENT_FILE.write_text(boot_id, encoding="utf-8")
        log("startup notification sent")
    else:
        log("startup notification already sent for current boot")

    log(f"bot running with python={python_path}, machine={machine_label(config)}")

    last_heartbeat = 0.0
    last_poll_error = ""
    while True:
        now = time.time()
        if now - last_heartbeat >= interval:
            HEARTBEAT_FILE.write_text(str(now), encoding="utf-8")
            last_heartbeat = now
        try:
            process_telegram_updates(config, telegram_config)
            last_poll_error = ""
        except (HTTPError, URLError, TimeoutError, RuntimeError, OSError) as exc:
            message = str(exc)
            if message != last_poll_error:
                log(f"telegram polling failed: {message}")
                last_poll_error = message
        time.sleep(telegram_poll_interval)


if __name__ == "__main__":
    raise SystemExit(main())
