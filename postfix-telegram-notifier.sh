#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Install script for Postfix → Telegram notifier daemon
#───────────────────────────────────────────────────────────────────────────────

# must run as root
if (( EUID != 0 )); then
  echo "Запускайте под root"
  exit 1
fi

# Проверяем зависимости
for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Требуется установить: $cmd"
    exit 1
  fi
done

# Вводим токен и ChatID
read -rp "Введите Telegram Bot Token: " BOT_TOKEN
[[ -n $BOT_TOKEN ]] || { echo "Ошибка: BOT_TOKEN не может быть пустым"; exit 1; }

read -rp "Введите Telegram Chat ID: " CHAT_ID
[[ -n $CHAT_ID ]] || { echo "Ошибка: CHAT_ID не может быть пустым"; exit 1; }

# Логи postfix
LOG=/var/log/mail.log
# Пути
BIN=/usr/local/bin
UNIT=/etc/systemd/system/postfix-telegram-notify.service

mkdir -p "$BIN"

# 1) helper-скрипт для отправки в Telegram
cat >"$BIN/telegram_notify.sh" <<EOF
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
    | jq -e '.ok' >/dev/null || \
    echo "\$(date): Ошибка отправки: \$msg" >> /var/log/postfix-telegram-notify.error.log
}
EOF
chmod 755 "$BIN/telegram_notify.sh"

# 2) демон-скрипт, который жует лог в реальном времени
cat >"$BIN/postfix-telegram-notify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/bin/telegram_notify.sh

LOG=/var/log/mail.log
HOST=$(hostname -f)

tail -n0 -F "$LOG" | while read -r line; do
  # ловим только bounced/deferred/reject
  if [[ $line =~ postfix/(smtp|local|lmtp|bounce) ]] && \
     ( [[ $line =~ NOQUEUE:\ reject: ]] || [[ $line =~ status=(bounced|deferred) ]] ); then

    ts=$(echo "$line" | cut -d' ' -f1-3)
    if [[ $line =~ NOQUEUE:\ reject: ]]; then
      to=$(grep -oP 'to=<\K[^>]+' <<<"$line")
      reason=$(sed -n 's/.*reject: \(.*\)/\1/p' <<<"$line")
      msg="⛔ Rejected @ $HOST
Time: $ts
To: $to
Reason: $reason"
    else
      id=$(grep -oP '\b[0-9A-F]{10,}\b' <<<"$line")
      to=$(grep -oP 'to=<\K[^>]+' <<<"$line")
      st=$(grep -oP 'status=\K[^ ]+' <<<"$line")
      msg="⚠️ Delivery issue @ $HOST
Time: $ts
QueueID: $id
To: $to
Status: $st"
    fi

    send_telegram "$msg"
  fi
done
EOF
chmod 755 "$BIN/postfix-telegram-notify.sh"

# 3) systemd-unit
cat >"$UNIT" <<EOF
[Unit]
Description=Postfix Telegram Notifier Daemon
After=network.target

[Service]
Type=simple
ExecStart=$BIN/postfix-telegram-notify.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 4) включаем и запускаем
systemctl daemon-reload
systemctl enable --now postfix-telegram-notify.service

echo
echo "✅ Готово! Демон запущен"
echo "Для логов ошибок Telegram: tail -f /var/log/postfix-telegram-notify.error.log"
