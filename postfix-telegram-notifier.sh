#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Инсталлер для Postfix → Telegram нотификатора (daemon на tail -F)

# Только под root
if [[ $EUID -ne 0 ]]; then
  echo "Запускайте под root"
  exit 1
fi

# Проверяем утилиты
for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Требуется установить: $cmd"
    exit 1
  fi
done

# Запрашиваем токен и чат
read -rp "Введите Telegram Bot Token: " BOT_TOKEN
[[ -n $BOT_TOKEN ]] || { echo "Token не может быть пустым"; exit 1; }

read -rp "Введите Telegram Chat ID: " CHAT_ID
[[ -n $CHAT_ID ]] || { echo "Chat ID не может быть пустым"; exit 1; }

# Пути
BIN_DIR=/usr/local/bin
SERVICE=/etc/systemd/system/postfix-telegram-notify.service

# Создаём папку для скриптов
mkdir -p "$BIN_DIR"

# 1) Helper: telegram_notify.sh
cat >"$BIN_DIR/telegram_notify.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"

send_telegram() {
  local msg="\$1"
  curl -fsSL --retry 3 --max-time 10 \\
    --data-urlencode "chat_id=\$CHAT_ID" \\
    --data-urlencode "text=\$msg" \\
    "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \\
    | jq -e '.ok' >/dev/null \
    || echo "\$(date): Ошибка отправки: \$msg" >> /var/log/postfix-telegram-notify.error.log
}
EOF
chmod 755 "$BIN_DIR/telegram_notify.sh"

# 2) Основной daemon-скрипт
cat >"$BIN_DIR/postfix-telegram-notify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/bin/telegram_notify.sh

LOG=/var/log/mail.log
HOST=$(hostname -f)

tail -n0 -F "$LOG" | while read -r line; do
  if [[ $line =~ postfix/(smtp|local|lmtp|bounce) ]] && \
     ( [[ $line =~ NOQUEUE:\ reject: ]] || [[ $line =~ status=(bounced|deferred) ]] ); then

    ts=$(echo "$line" | cut -d' ' -f1-3)
    if [[ $line =~ NOQUEUE:\ reject: ]]; then
      to=$(grep -oP 'to=<\K[^>]+' <<<"$line")
      reason=$(sed -n 's/.*reject: \(.*\)/\1/p' <<<"$line")
      msg="⛔ Rejected @ $HOST\nTime: $ts\nTo: $to\nReason: $reason"
    else
      id=$(grep -oP '\b[0-9A-F]{10,}\b' <<<"$line")
      to=$(grep -oP 'to=<\K[^>]+' <<<"$line")
      st=$(grep -oP 'status=\K[^ ]+' <<<"$line")
      msg="⚠️ Delivery issue @ $HOST\nTime: $ts\nQueueID: $id\nTo: $to\nStatus: $st"
    fi

    send_telegram "$msg"
  fi
done
EOF
chmod 755 "$BIN_DIR/postfix-telegram-notify.sh"

# 3) systemd unit
cat >"$SERVICE" <<EOF
[Unit]
Description=Postfix Telegram Notifier Daemon
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/postfix-telegram-notify.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 4) Запуск через systemd
systemctl daemon-reload
systemctl enable --now postfix-telegram-notify.service

echo "Установлено! Демон запущен и следит за $LOG"
