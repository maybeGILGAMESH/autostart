import pathlib
import sys
import tempfile
import unittest
import importlib.util
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "test_env_bot.py"

spec = importlib.util.spec_from_file_location("autostart_test_env_bot", MODULE_PATH)
assert spec is not None
test_env_bot = importlib.util.module_from_spec(spec)
sys.modules["autostart_test_env_bot"] = test_env_bot
assert spec.loader is not None
spec.loader.exec_module(test_env_bot)


class MachineCommandTests(unittest.TestCase):
    def test_parse_slash_command_with_bot_suffix(self) -> None:
        command, target, args = test_env_bot.parse_bot_command("/update@my_bot usr7 now")

        self.assertEqual(command, "update")
        self.assertEqual(target, "usr7")
        self.assertEqual(args, ["now"])

    def test_machine_matches_configured_alias(self) -> None:
        config = {
            "BOT_MACHINE_NAME": "user",
            "BOT_MACHINE_ALIASES": "user,user-System-Product-Name",
        }

        with mock.patch.object(test_env_bot.socket, "gethostname", return_value="user-System-Product-Name"):
            self.assertTrue(test_env_bot.machine_matches(config, "USER"))
            self.assertTrue(test_env_bot.machine_matches(config, "user-System-Product-Name"))
            self.assertFalse(test_env_bot.machine_matches(config, "usr7"))

    def test_add_machine_alias_persists_local_alias(self) -> None:
        config = {"BOT_MACHINE_NAME": "user", "BOT_MACHINE_ALIASES": "user"}

        with tempfile.TemporaryDirectory() as tmpdir:
            aliases_file = pathlib.Path(tmpdir) / "aliases.json"
            with mock.patch.object(test_env_bot, "MACHINE_ALIASES_FILE", aliases_file):
                reply = test_env_bot.add_machine_alias(config, "usr7")

                self.assertIn("usr7", reply)
                self.assertTrue(test_env_bot.machine_matches(config, "usr7"))

    def test_foreign_known_update_is_not_acknowledged(self) -> None:
        bot_config = {
            "BOT_MACHINE_NAME": "user",
            "BOT_MACHINE_ALIASES": "user",
            "BOT_KNOWN_MACHINES": "user,usr7",
            "BOT_FOREIGN_COMMAND_BACKOFF_SECONDS": "0",
        }
        telegram_config = {"TELEGRAM_ENABLED": "1", "TG_CHAT_ID": "42"}
        response = {
            "result": [
                {
                    "update_id": 100,
                    "message": {
                        "chat": {"id": 42},
                        "text": "update usr7",
                        "message_id": 7,
                    },
                }
            ]
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = pathlib.Path(tmpdir)
            with (
                mock.patch.object(test_env_bot, "TELEGRAM_HELD_UPDATES_FILE", tmp_path / "held.json"),
                mock.patch.object(test_env_bot, "TELEGRAM_BACKOFF_NOTIFIED_FILE", tmp_path / "notified.json"),
                mock.patch.object(test_env_bot, "load_telegram_offset", return_value=0),
                mock.patch.object(test_env_bot, "telegram_api", return_value=response),
                mock.patch.object(test_env_bot, "save_telegram_offset") as save_offset,
                mock.patch.object(test_env_bot, "send_telegram_reply") as send_reply,
                mock.patch.object(test_env_bot, "send_status_email") as send_status,
                mock.patch.object(test_env_bot.time, "sleep"),
            ):
                test_env_bot.process_telegram_updates(bot_config, telegram_config)

            save_offset.assert_not_called()
            send_reply.assert_not_called()
            send_status.assert_called_once()


if __name__ == "__main__":
    unittest.main()
