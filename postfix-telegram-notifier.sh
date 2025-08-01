#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Install.sh — ставит Postfix→Telegram tail-F-демон
# ──────────────────────────────────────────────────────────────────────────────

# 0) Проверка на root
(( EUID == 0 )) || { echo "Запускать под root!"; exit 1; }

# 1) Проверяем зависимости
for cmd in curl jq tail systemctl; do
  command -v "$cmd" &>/dev/null || { echo "Нужна утилита: $cmd"; exit 1; }
done

# 2) Запрашиваем у пользователя
read -rp "Введите Telegram Bot Token: " BOT_TOKEN
[[ -n $BOT_TOKEN ]] || { echo "Token не может быть пустым"; exit 1; }

read -rp "Введите Telegram Chat ID: " CHAT_ID
[[ -n $CHAT_ID ]] || { echo "Chat ID не может быть пустым"; exit 1; }

# 3) Пути
BIN=/usr/local/bin
UNIT=/etc/systemd/system/postfix-telegram-notify.service

mkdir -p "$BIN"

# 4) Пишем helper для отправки в Telegram
cat >"$BIN/telegram_notify.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"

send_telegram(){
  curl -fsSL --retry 3 --max-time 10 \\
    --data-urlencode "chat_id=\$CHAT_ID" \\
    --data-urlencode "text=\$1" \\
    "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
    | jq -e '.ok' >/dev/null
}
EOF
chmod 755 "$BIN/telegram_notify.sh"

# 5) Пишем основной демон-скрипт на tail -F
cat >"$BIN/postfix-telegram-notify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/bin/telegram_notify.sh

LOG=/var/log/mail.log
HOST=$(hostname -f)

tail -n0 -F "$LOG" | while read -r line; do
  # только bounced/deferred/reject
  if [[ $line =~ postfix/(smtp|local|lmtp|bounce) ]] && \
     ( [[ $line =~ status=(bounced|deferred) ]] || [[ $line =~ NOQUEUE:\ reject: ]] ); then

    ts=$(echo "$line" | cut -d' ' -f1-3)

    if [[ $line =~ NOQUEUE:\ reject: ]]; then
      to=$(grep -oP 'to=<\K[^>]+' <<<"$line")
      reason=$(sed -n 's/.*reject: \(.*\)/\1/p' <<<"$line")
      send_telegram "⛔ Rejected @ $HOST
Time: $ts
To: $to
Reason: $reason"
    else
      id=$(grep -oP '\b[0-9A-F]{10,}\b' <<<"$line")
      to=$(grep -oP 'to=<\K[^>]+' <<<"$line")
      st=$(grep -oP 'status=\K[^ ]+' <<<"$line")
      send_telegram "⚠️ Delivery issue @ $HOST
Time: $ts
QueueID: $id
To: $to
Status: $st"
    fi

  fi
done
EOF
chmod 755 "$BIN/postfix-telegram-notify.sh"

# 6) Пишем systemd-unit
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

# 7) Перезагружаем и включаем сервис
systemctl daemon-reload
systemctl enable --now postfix-telegram-notify.service

echo
echo "✅ Готово! Демон запущен и следит за /var/log/mail.log"
echo "   Проверить статус: systemctl status postfix-telegram-notify.service"
echo "   Для логов ошибок Telegram: journalctl -u postfix-telegram-notify.service"
