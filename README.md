# Autostart Stack

## Обновление 2026-05-06

Теперь схема запуска и уведомлений разделена явно:

- по умолчанию стартует raw TCP-туннель `tuna tcp 22`, чтобы удаленный порт отдавал настоящий SSH banner локального `sshd`
- старый режим `tuna ssh` можно вернуть через `TUNA_TUNNEL_MODE=ssh` в `tuna_config.env`
- в `tcp`-режиме Tuna не генерирует одноразовый пароль; доступ идет в локальный `sshd`, пароль берется у Linux-пользователя или из SSH-ключа. Если в отчетах нужен literal password, задайте `TUNA_ACCESS_PASSWORD=` в `tuna_config.env`
- Tuna стартует только напрямую, без `http_proxy` и `https_proxy`
- Telegram-уведомления идут через локальный proxy `127.0.0.1:12334`, если он доступен
- headless-режим `tuna` больше не ждёт живой proxy перед запуском SSH-сессии

Это нужно для сценария, где `tuna` работает только в direct-режиме, а Telegram API, наоборот, доступен только через локальный Hiddify proxy.

Этот проект настроен так, чтобы после запуска или перезапуска компьютера стек поднимался автоматически.

Что должно происходить после старта системы:

1. Поднимается `VNC :1`
2. Стартует `Hiddify` и проходит цикл проверки:
   `старт -> ожидание 15 секунд -> остановка -> повторный старт`
3. Запускается `tuna ssh`
4. Если графический запуск `tuna` не удержал процесс, включается резервный headless-запуск
5. Поднимается Python-бот в `conda env test`
6. Все основные шаги пишут логи в папку `logs/`
7. Раз в 24 часа запускается health-check
8. Раз в 2 часа отправляется обычный статус-репорт в почту и в Telegram
9. При проблемах алерты отправляются в почту и в Telegram, если они включены в конфиге

Важно:

- Компьютер не перезагружается каждые 24 часа просто по расписанию
- Раз в 24 часа запускается проверка состояния
- Если проверка находит проблему, система сначала пытается восстановиться сама
- Если восстановление не помогло и `AUTO_REBOOT_ENABLED=1`, тогда выполняется автоперезагрузка

Что видно в статусе и отчетах:

- состояние `VNC`, `Hiddify`, `tuna`, Python-бота
- включен ли автоподъем через `GNOME autostart`, `crontab @reboot` и `systemd`
- любые процессы `tuna`, не только `tuna ssh`
- отдельно `tuna ssh` и `tuna http`
- слушающие порты `tuna`
- последние строки логов и сервисного состояния

Это значит, что если вы вручную поднимете `tuna ssh` или `tuna http` в любом терминале, они тоже попадут в `status_all.sh` и в полный статус-репорт.

Для автозапущенного `tuna ssh` система дополнительно умеет вылавливать и сохранять:

- удаленный `host`
- удаленный `port`
- пароль сессии
- готовую `ssh`-команду
- строку для `known_hosts`

Эти данные сохраняются в:

- `/home/user/autostart/generated/tuna_access_latest.txt`
- `/home/user/autostart/generated/tuna_access_latest.env`

И при появлении новых реквизитов доступа автоматически отправляются в почту и в Telegram.

Важно:

- этот перехват гарантирован для управляемого автозапуском `tuna ssh`
- если вы запустите `tuna ssh` вручную в случайном терминале вне наших скриптов, общий статус его увидит, но пароль такой сессии автоматически пойман может не быть
- для автозапуска `tuna ssh` proxy-переменные окружения теперь принудительно очищаются
- для Telegram-уведомлений система отдельно пытается использовать `http://127.0.0.1:12334`

## Основные файлы

- `autostart_tuna.sh` — запуск `tuna ssh` и отправка boot-report на почту
- `hiddify_autostart.sh` — старт и переподключение Hiddify
- `vnc_keepalive.sh` — поддержание `VNC :1`
- `fallback_orchestrator.sh` — резервный сценарий, если основной автозапуск не поднял стек
- `tuna_headless.sh` — резервный `tuna ssh` без GUI
- `health_check.sh` — суточная проверка и автоперезагрузка
- `test_env_bot.py` — Python-бот в окружении `test`
- `stop_all.sh` — ручная остановка всего стека
- `telegram_config.env` — настройки Telegram-уведомлений

## Что уже включено

- Пользовательский автозапуск через `~/.config/autostart`
- `crontab @reboot /home/user/autostart/cron_reboot.sh`
- Systemd fallback через:
  - `autostart-vnc-keepalive.service`
  - `autostart-fallback.service`
- `autostart-test-bot.service`
- `autostart-tuna-backup.service`
- `autostart-healthcheck.timer`
- `autostart-periodic-status.timer`

То есть сейчас схема двухконтурная:

- первый контур: пользовательский автозапуск и `crontab @reboot`
- второй контур: systemd fallback и резервные сервисы

Это сделано затем, чтобы после перезагрузки система поднималась автономно даже если один из путей старта не сработал.

## Полезные команды

Проверить весь стек:

```bash
/home/user/autostart/status_all.sh
```

Эта команда и полный статус-репорт теперь показывают не только `tuna ssh`, но и любые процессы `tuna`, включая `tuna http`, если вы поднимете их вручную или через систему.
Там же выводятся слушающие порты `tuna` и последние строки логов `autostart-tuna-backup.service`.

Собрать и отправить полный статус по почте и в Telegram:

```bash
/home/user/autostart/send_full_status_report.sh send
```

В этот отчет сейчас входят:

- дата, время, hostname и пользователь
- статусы основных компонентов
- признаки включенного автозапуска
- `tuna any`, `tuna ssh`, `tuna http`
- порты `tuna`
- последний сохраненный блок `Tuna Access`, если он уже был пойман
- список процессов
- хвосты последних логов

Собрать и просто посмотреть отчет без отправки:

```bash
/home/user/autostart/send_full_status_report.sh preview
```

Открыть в Firefox письмо через `mailto`, чтобы осталось только нажать `Отправить`:

```bash
/home/user/autostart/send_full_status_report.sh mailto
```

Остановить все вручную:

```bash
/home/user/autostart/stop_all.sh
```

Локально прогнать систему без перезагрузки:

```bash
/home/user/autostart/debug_run.sh live
```

Локально прогнать без отправки писем:

```bash
/home/user/autostart/debug_run.sh safe
```

Показать статус и последние логи:

```bash
/home/user/autostart/debug_run.sh status
```

Проверить ключевые systemd-статусы одной командой:

```bash
systemctl is-active autostart-vnc-keepalive.service autostart-fallback.service autostart-test-bot.service autostart-tuna-backup.service autostart-healthcheck.timer autostart-periodic-status.timer
```

Проверить systemd-сервисы:

```bash
systemctl status autostart-vnc-keepalive.service
systemctl status autostart-fallback.service
systemctl status autostart-test-bot.service
systemctl status autostart-tuna-backup.service
systemctl status autostart-healthcheck.timer
systemctl status autostart-periodic-status.timer
```

Посмотреть логи:

```bash
tail -f /home/user/autostart/logs/vnc_keepalive.log
tail -f /home/user/autostart/logs/fallback_orchestrator.log
tail -f /home/user/autostart/logs/test_env_bot.log
tail -f /home/user/autostart/logs/health_check.log
tail -f /home/user/autostart/logs/autostart.log
tail -f /home/user/autostart/logs/hiddify_autostart.log
tail -f /home/user/autostart/logs/tuna_headless.log
tail -f /home/user/autostart/logs/periodic_status.log
```

Формат логов:

- логи не удаляются автоматически
- новые файлы создаются по часам
- рабочий формат имени: `name_YYYYMMDD_HH.log`
- короткие имена вроде `autostart.log` или `tuna_headless.log` указывают на текущий почасовой файл

## Отключение автоперезагрузки одной командой

Отключить:

```bash
/home/user/autostart/toggle_auto_reboot.sh off
```

Включить обратно:

```bash
/home/user/autostart/toggle_auto_reboot.sh on
```

Флаг хранится в `health_config.env` в строке `AUTO_REBOOT_ENABLED=...`.

Это выключает только автоматический `reboot` после неуспешного health-check.
Сам health-check раз в 24 часа при этом продолжит работать и слать алерты.

## Периодическая отправка статуса раз в 2 часа

Обычный полный статус теперь отправляется автоматически каждые 2 часа через:

- `autostart-periodic-status.service`
- `autostart-periodic-status.timer`

Если нужно вручную запустить такую отправку прямо сейчас:

```bash
systemctl start autostart-periodic-status.service
```

Если нужно отключить именно периодическую рассылку статуса:

```bash
sudo systemctl disable --now autostart-periodic-status.timer
```

Включить обратно:

```bash
sudo systemctl enable --now autostart-periodic-status.timer
```

Если нужна ручная проверка без ожидания 24 часов:

```bash
sudo systemctl start autostart-healthcheck.service
```

## Почта

Почта отправляется через настройки из `mail_config.env`.
Если SMTP настроен корректно, то:

- `send_full_status_report.sh send` отправляет полный статус на почту и в Telegram
- аварийные уведомления тоже уходят автоматически

## Команды через Telegram

`autostart-test-bot.service` читает входящие сообщения Telegram от `TG_CHAT_ID` из `telegram_config.env`.

Поддерживаются команды:

```text
update <machine>
status [machine]
machines
addmachine <name>
```

`update <machine>` перезапускает `tuna ssh/tcp` только если `<machine>` совпадает с локальным именем или alias текущей машины. После обновления бот отвечает сообщением с именем машины, hostname и актуальным блоком `Tuna Access`, включая пароль для режима `TUNA_TUNNEL_MODE=ssh`.

`status` отправляет последний сохраненный доступ без перезапуска туннеля.

`machines` показывает локальные имена этой машины и список известных машин.

`addmachine <name>` добавляет локальный alias для текущей машины в `generated/test_env_bot.machine_aliases.json`.

Имена машин задаются в `test_bot.env`:

```bash
BOT_MACHINE_NAME=user
BOT_MACHINE_ALIASES=user,user-System-Product-Name
BOT_KNOWN_MACHINES=user,usr7
BOT_FOREIGN_COMMAND_BACKOFF_SECONDS=30
BOT_INVALID_TARGET_ACK_SECONDS=45
BOT_BACKOFF_NOTIFY_ENABLED=1
```

Если несколько машин слушают один `TG_BOT_TOKEN`, бот работает в cooperative-режиме:

- команда для известной другой машины не подтверждается через Telegram offset;
- нецелевая машина ждет `BOT_FOREIGN_COMMAND_BACKOFF_SECONDS`, чтобы целевая машина забрала этот же update;
- при уходе в ожидание бот отправляет уведомление, что polling `getUpdates` на этой машине временно уступил очередь;
- неизвестное или синтаксически неверное имя машины удерживается до `BOT_INVALID_TARGET_ACK_SECONDS`, затем подтверждается с ошибкой, чтобы очередь не зависла навсегда.

Команды из других Telegram-чатов игнорируются.

Принимать команды письмами тоже можно, но это лучше делать отдельным IMAP-слоем с allowlist отправителя, уникальным `Message-ID` и командным паролем в теме/теле письма. Telegram уже закрыт `TG_CHAT_ID`, отвечает быстрее и не требует хранения дополнительного IMAP-доступа.

Быстрая проверка SMTP:

```bash
python3 /home/user/autostart/send_status_email.py /home/user/autostart/mail_config.env "SMTP test from {hostname}" "Проверка SMTP"
```

## Telegram

Для Telegram заполните `telegram_config.env`:

- `TELEGRAM_ENABLED=1`
- `TG_BOT_TOKEN=...`
- `TG_CHAT_ID=...`

Если Telegram не настроен, алерты туда отправляться не будут.

Если токен уже есть, а `chat_id` еще не знаете:

1. Напишите любое сообщение вашему боту в Telegram
2. Запустите:

```bash
python3 /home/user/autostart/telegram_get_chat_id.py
```

Скрипт сам сохранит `TG_CHAT_ID` в `telegram_config.env`.

Если Telegram настроен, тестовые и аварийные уведомления будут приходить туда автоматически вместе с почтовыми уведомлениями.

## Python окружение

Python-скрипты сейчас используют только стандартную библиотеку Python. Файл `requirements.txt` оставлен как стабильная точка для будущих зависимостей.

Создать или обновить conda-окружение:

```bash
conda env update -f environment.yml --prune
```

Проверить запуск Python-части:

```bash
conda run -n test python -m py_compile test_env_bot.py capture_tuna_access.py send_status_email.py send_boot_report.py telegram_get_chat_id.py
```

`run_test_bot.sh` по умолчанию ищет `conda` через `PATH`. Если conda лежит в нестандартном месте, задайте:

```bash
CONDA_BIN=/path/to/conda /home/user/autostart/run_test_bot.sh
```

После клона создайте локальные конфиги из примеров и заполните секреты только в локальных `*.env`:

```bash
cp autostart_config.env.example autostart_config.env
cp mail_config.env.example mail_config.env
cp telegram_config.env.example telegram_config.env
cp test_bot.env.example test_bot.env
cp tuna_config.env.example tuna_config.env
cp vnc_config.env.example vnc_config.env
cp hiddify_config.env.example hiddify_config.env
cp fallback_config.env.example fallback_config.env
cp health_config.env.example health_config.env
```

Сначала настройте `autostart_config.env`. Это главный переносимый файл для пользователя, домашней директории, пути проекта, UID, conda и Hiddify:

```bash
AUTOSTART_USER=user
AUTOSTART_GROUP=user
AUTOSTART_HOME=/home/user
AUTOSTART_DIR=/home/user/autostart
AUTOSTART_UID=1000
AUTOSTART_CONDA_BIN=/home/user/conda/bin/conda
AUTOSTART_HIDDIFY_APPIMAGE=/home/user/Downloads/Hiddify-Linux-x64.AppImage
```

На другой машине обычно достаточно поменять `AUTOSTART_USER`, `AUTOSTART_GROUP`, `AUTOSTART_HOME`, `AUTOSTART_DIR`, `AUTOSTART_UID` и пути к conda/Hiddify. После этого примените конфиг ко всем зависимым файлам:

```bash
bash /home/user/autostart/render_autostart_config.sh
```

## Подготовка к Git

Перед публикацией не коммитьте реальные `*.env`, `logs/`, `generated/` и `__pycache__/`; они закрыты через `.gitignore`.

Проверить, что секреты и runtime-файлы игнорируются:

```bash
git check-ignore -v mail_config.env telegram_config.env logs generated __pycache__
```

Если текущая `.git` папка повреждена или пуста и `git status` пишет `fatal: not a git repository`, удалите пустой каталог и создайте репозиторий заново:

```bash
rmdir .git
git init
git branch -M main
git add .
git status --short
git commit -m "Prepare bot environment and machine-targeted Telegram commands"
git remote add origin https://github.com/<OWNER>/<REPO>.git
git push -u origin main
```

При `git push` введите GitHub login как username, а personal access token как password.

Одноразовый push без сохранения token в remote URL:

```bash
read -rsp 'GitHub token: ' GITHUB_TOKEN; echo
git push -u "https://x-access-token:${GITHUB_TOKEN}@github.com/<OWNER>/<REPO>.git" main
unset GITHUB_TOKEN
```

## Развертывание на другой машине

Базовые системные зависимости:

- `git`
- `conda`
- `vncserver`/TigerVNC
- `systemd`
- `tuna`
- `gnome-terminal`, если нужен интерактивный terminal-запуск
- Hiddify AppImage, если используете локальный Telegram proxy

Клонировать проект:

```bash
cd /home/user
git clone https://github.com/<OWNER>/<REPO>.git autostart
cd /home/user/autostart
```

Создать локальные конфиги:

```bash
cp mail_config.env.example mail_config.env
cp telegram_config.env.example telegram_config.env
cp test_bot.env.example test_bot.env
cp tuna_config.env.example tuna_config.env
cp vnc_config.env.example vnc_config.env
cp hiddify_config.env.example hiddify_config.env
cp fallback_config.env.example fallback_config.env
cp health_config.env.example health_config.env
```

Заполнить минимум:

- `autostart_config.env`: пользователь, группа, home, путь проекта, uid, conda, Hiddify
- `telegram_config.env`: `TELEGRAM_ENABLED=1`, `TG_BOT_TOKEN`, `TG_CHAT_ID`
- `mail_config.env`: SMTP-настройки, если нужны письма
- `test_bot.env`: `BOT_MACHINE_NAME`, `BOT_MACHINE_ALIASES`, `BOT_KNOWN_MACHINES`
- `hiddify_config.env`: путь к `HIDDIFY_APPIMAGE`
- `tuna_config.env`: режим `TUNA_TUNNEL_MODE` и параметры tuna

Применить единый конфиг к systemd/desktop/env-файлам:

```bash
bash /home/user/autostart/render_autostart_config.sh
```

Создать/обновить Python-окружение:

```bash
conda env update -f environment.yml --prune
conda run -n test python -m py_compile test_env_bot.py capture_tuna_access.py send_status_email.py send_boot_report.py telegram_get_chat_id.py
```

Установить автозапуск без systemd:

```bash
/home/user/autostart/install_autostart.sh
```

Установить полный автономный режим с systemd:

```bash
/home/user/autostart/install_full_autonomy.sh
```

Проверить состояние:

```bash
/home/user/autostart/status_all.sh
systemctl is-active autostart-vnc-keepalive.service autostart-fallback.service autostart-test-bot.service autostart-tuna-backup.service autostart-healthcheck.timer autostart-periodic-status.timer
```

Проверить Telegram-команды:

```text
machines
status <machine>
update <machine>
```

## Итоговое поведение

В нормальном режиме после включения или перезагрузки компьютера должны автоматически подняться:

- `VNC`
- `Hiddify`
- `tuna ssh`
- Python-бот в окружении `test`

Все это должно писать состояние и шаги в логи.
Логи не удаляются автоматически и складываются по часам.

Через 24 часа система не обязана перезагружаться.
Через 24 часа запускается health-check.
Перезагрузка происходит только если:

- проверка нашла проблему
- попытка самовосстановления не помогла
- `AUTO_REBOOT_ENABLED=1`

Отдельно от этого каждые 2 часа уходит обычный статус-репорт без перезагрузки и без попытки лечения.
- `AUTO_REBOOT_ENABLED=1`
