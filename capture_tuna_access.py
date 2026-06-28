#!/usr/bin/env python3
import argparse
import hashlib
import os
import re
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
STATE_DIR = BASE_DIR / "generated"
LOG_DIR = BASE_DIR / "logs"
MAIL_CONFIG = BASE_DIR / "mail_config.env"
BOT_CONFIG = BASE_DIR / "test_bot.env"
SEND_STATUS = BASE_DIR / "send_status_email.py"
NOTIFY_TIMEOUT_SECONDS = 120
DEFAULT_TUNA_BIN = os.environ.get("TUNA_BIN") or "tuna"
DIRECT_PROXY_ENV_KEYS = (
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "no_proxy",
    "NO_PROXY",
)


def load_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def to_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def machine_name() -> str:
    config = load_env(BOT_CONFIG)
    return config.get("BOT_MACHINE_NAME", "").strip() or socket.gethostname()


def machine_label() -> str:
    name = machine_name()
    hostname = socket.gethostname()
    if name == hostname:
        return name
    return f"{name} ({hostname})"


def utc_now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat()


def sanitize_line(line: str) -> str:
    return re.sub(r"(password:\s*)(\S+)", r"\1[hidden]", line, flags=re.IGNORECASE)


def extract_message_payload(line: str) -> str:
    match = re.search(r'msg="(?P<msg>.*)"$', line)
    if match:
        return match.group("msg")
    return line


def append_capture_log(mode: str, message: str) -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"tuna_capture_{mode}_{datetime.now().strftime('%Y%m%d_%H')}.log"
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(f"[{utc_now()}] {message}\n")


def build_block(info: dict[str, str]) -> str:
    lines = [
        "Tuna Access",
        "===========",
        f"Updated at: {info.get('updated_at', '')}",
        f"Machine: {info.get('machine', machine_name())}",
        f"Hostname: {socket.gethostname()}",
        f"Mode: {info.get('mode', '')}",
        f"Tunnel mode: {info.get('tunnel_mode', '')}",
        f"Local target: {info.get('local_target', '')}",
        f"PID: {info.get('pid', '')}",
        f"Forwarding: {info.get('forwarding', '')}",
        f"Host: {info.get('host', '')}",
        f"Port: {info.get('port', '')}",
        f"SSH command: {info.get('ssh_command', '')}",
    ]
    if info.get("password"):
        lines.append(f"Password: {info.get('password', '')}")
    elif info.get("tunnel_mode") == "tcp":
        lines.append(f"Login: {info.get('ssh_user', '')}")
        lines.append("Password: local Linux user password or SSH key")
    if info.get("known_hosts"):
        lines.append(f"Known hosts: {info.get('known_hosts', '')}")
    return "\n".join(lines).strip() + "\n"


def write_access_files(info: dict[str, str]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    env_path = STATE_DIR / "tuna_access_latest.env"
    txt_path = STATE_DIR / "tuna_access_latest.txt"
    hash_path = STATE_DIR / "tuna_access_latest.hash"

    env_lines = []
    for key in [
        "updated_at",
        "mode",
        "tunnel_mode",
        "local_target",
        "pid",
        "forwarding",
        "host",
        "port",
        "password",
        "ssh_user",
        "ssh_command",
        "known_hosts",
        "machine",
    ]:
        value = info.get(key, "").replace("\n", " ").replace("\r", " ").strip()
        env_key = f"TUNA_ACCESS_{key.upper()}"
        env_lines.append(f'{env_key}="{value}"')
    env_path.write_text("\n".join(env_lines) + "\n", encoding="utf-8")
    txt_path.write_text(build_block(info), encoding="utf-8")

    fingerprint = hashlib.sha256(
        "|".join(
            [
                info.get("mode", ""),
                info.get("host", ""),
                info.get("port", ""),
                info.get("password", ""),
                info.get("ssh_command", ""),
            ]
        ).encode("utf-8")
    ).hexdigest()
    hash_path.write_text(fingerprint + "\n", encoding="utf-8")


def previous_hash() -> str:
    hash_path = STATE_DIR / "tuna_access_latest.hash"
    if not hash_path.exists():
        return ""
    return hash_path.read_text(encoding="utf-8").strip()


def notify_access(info: dict[str, str], enabled: bool) -> bool:
    if not enabled or not MAIL_CONFIG.exists() or not SEND_STATUS.exists():
        return True

    subject = f"Tuna access updated on {machine_label()}"
    body = build_block(info)
    try:
        result = subprocess.run(
            [sys.executable, str(SEND_STATUS), str(MAIL_CONFIG), subject, body],
            check=False,
            capture_output=True,
            text=True,
            timeout=NOTIFY_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        output = "\n".join(part for part in [(exc.stdout or "").strip(), (exc.stderr or "").strip()] if part)
        if output:
            append_capture_log(info.get("mode", "headless"), f"notification timeout output: {output}")
        append_capture_log(
            info.get("mode", "headless"),
            f"notification timed out after {NOTIFY_TIMEOUT_SECONDS}s",
        )
        return False
    output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
    if output:
        append_capture_log(info.get("mode", "headless"), f"notification output: {output}")
    if result.returncode != 0:
        append_capture_log(info.get("mode", "headless"), f"notification failed with status {result.returncode}")
        return False
    return True


def parse_line(info: dict[str, str], line: str) -> None:
    payload = extract_message_payload(line).strip()

    forwarding_match = re.search(r"Forwarding tcp://([^:/\s]+):(\d+)\s*->\s*(.+)$", payload)
    if forwarding_match:
        info["host"] = forwarding_match.group(1)
        info["port"] = forwarding_match.group(2)
        info["local_target"] = forwarding_match.group(3).strip()
        info["forwarding"] = forwarding_match.group(0)
        if info.get("tunnel_mode") == "tcp" and not info.get("ssh_command"):
            ssh_user = info.get("ssh_user", "")
            target = f"{ssh_user}@{info['host']}" if ssh_user else info["host"]
            info["ssh_command"] = f"ssh -p {info['port']} {target}"

    password_match = re.search(r"password:\s*(\S+)$", payload, re.IGNORECASE)
    if password_match:
        info["password"] = password_match.group(1).strip().strip('"').strip("'")

    ssh_candidate = re.search(r"\bssh\b.*$", payload)
    if ssh_candidate and re.search(r"(?:^|\s)-p\s+\d+\b", ssh_candidate.group(0)):
        info["ssh_command"] = ssh_candidate.group(0).strip().strip("`")

    if info.get("ssh_command"):
        port_first_match = re.search(r"\bssh\b.*\b-p\s+(?P<port>\d+)\b.*\s(?P<target>\S+)$", info["ssh_command"])
        target_first_match = re.search(r"\bssh\b\s+(?P<target>\S+)\b.*\b-p\s+(?P<port>\d+)\b", info["ssh_command"])
        ssh_match = port_first_match or target_first_match
        if ssh_match:
            info["port"] = info.get("port") or ssh_match.group("port")
            target = ssh_match.group("target").strip().strip("`")
            info["host"] = info.get("host") or target.split("@")[-1]

    known_hosts_match = re.search(
        r'echo\s+\\"(?P<known_hosts>\[[^]]+\].+?)\\"\s*>>\s*~/.ssh/known_hosts',
        payload,
    )
    if known_hosts_match:
        info["known_hosts"] = known_hosts_match.group("known_hosts")


def info_complete(info: dict[str, str]) -> bool:
    required = ["host", "port", "ssh_command"]
    if not all(info.get(key) for key in required):
        return False
    if info.get("tunnel_mode") == "ssh":
        return bool(info.get("password"))
    return True


def fingerprint(info: dict[str, str]) -> str:
    return hashlib.sha256(
        "|".join(
            [
                info.get("mode", ""),
                info.get("tunnel_mode", ""),
                info.get("local_target", ""),
                info.get("host", ""),
                info.get("port", ""),
                info.get("password", ""),
                info.get("ssh_user", ""),
                info.get("ssh_command", ""),
            ]
        ).encode("utf-8")
    ).hexdigest()


def build_tuna_env() -> dict[str, str]:
    env = os.environ.copy()
    for key in DIRECT_PROXY_ENV_KEYS:
        env.pop(key, None)
    return env


def build_tuna_command(tuna_bin: str, tuna_config: dict[str, str]) -> tuple[list[str], str, str, str]:
    tunnel_mode = tuna_config.get("TUNA_TUNNEL_MODE", "tcp").strip().lower()
    location = tuna_config.get("TUNA_LOCATION", "").strip()
    remote_port = tuna_config.get("TUNA_REMOTE_PORT", "").strip()

    if tunnel_mode == "ssh":
        command = [tuna_bin, "--no-colors", "ssh"]
        local_target = "127.0.0.1:22"
    elif tunnel_mode == "tcp":
        local_target = tuna_config.get("TUNA_TCP_TARGET", "22").strip() or "22"
        command = [tuna_bin, "--no-colors", "tcp", local_target]
    else:
        raise ValueError(f"Unsupported TUNA_TUNNEL_MODE={tunnel_mode!r}; use tcp or ssh")

    if location:
        command.extend(["--location", location])
    if remote_port:
        command.extend(["--port", remote_port])

    return command, tunnel_mode, local_target, tuna_config.get("TUNA_SSH_USER", os.environ.get("USER", "")).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["interactive", "headless"], required=True)
    parser.add_argument("--echo", action="store_true")
    parser.add_argument("--tuna-bin", default=DEFAULT_TUNA_BIN)
    args = parser.parse_args()

    tuna_config = load_env(BASE_DIR / "tuna_config.env")
    notify_enabled = to_bool(tuna_config.get("TUNA_ACCESS_NOTIFY_ENABLED"), True)

    try:
        command, tunnel_mode, local_target, ssh_user = build_tuna_command(args.tuna_bin, tuna_config)
    except ValueError as exc:
        append_capture_log(args.mode, str(exc))
        print(exc, file=sys.stderr)
        return 2

    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=build_tuna_env(),
    )

    info = {
        "updated_at": utc_now(),
        "mode": args.mode,
        "tunnel_mode": tunnel_mode,
        "local_target": local_target,
        "ssh_user": ssh_user,
        "pid": str(process.pid),
        "forwarding": "",
        "host": "",
        "port": "",
        "password": tuna_config.get("TUNA_ACCESS_PASSWORD", "").strip() if tunnel_mode == "tcp" else "",
        "ssh_command": "",
        "known_hosts": "",
        "machine": machine_name(),
    }
    write_access_files(info)

    sent_fingerprint = ""
    append_capture_log(args.mode, f"starting tuna access capture with command: {' '.join(command)}")
    append_capture_log(args.mode, "tuna launch mode: direct without proxy environment")
    try:
        assert process.stdout is not None
        for raw_line in process.stdout:
            line = raw_line.rstrip("\n")
            append_capture_log(args.mode, sanitize_line(line))
            parse_line(info, line)
            if args.echo:
                sys.stdout.write(raw_line)
                sys.stdout.flush()
            if info_complete(info):
                info["updated_at"] = utc_now()
                new_fingerprint = fingerprint(info)
                if new_fingerprint != sent_fingerprint:
                    write_access_files(info)
                    append_capture_log(args.mode, "captured updated tuna access details")
                    if notify_access(info, notify_enabled):
                        sent_fingerprint = new_fingerprint

        status = process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    if not info_complete(info):
        append_capture_log(args.mode, f"tuna exited with status {status} before full access details were captured")
    else:
        append_capture_log(args.mode, f"tuna exited with status {status}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
