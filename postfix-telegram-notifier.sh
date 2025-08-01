#!/usr/bin/env bash
set -euo pipefail

# must be root
(( EUID == 0 )) || { echo "Запускайте под root"; exit 1; }

# deps
for cmd in journalctl curl jq date; do
  command -v "$cmd" >/dev/null || { echo "Требуется: $cmd"; exit 1; }
done

read -rp "Введите Telegram Bot Token: " BOT_TOKEN
[[ -n $BOT_TOKEN ]] || exit 1

read -rp "Введите Telegram Chat ID: " CHAT_ID
[[ -n $CHAT_ID ]] || exit 1

BIN=/usr/local/bin
mkdir -p "$BIN"

# helper
cat >"$BIN/telegram_notify.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
send_telegram(){
  curl -fsSL --retry 3 --max-time 10 \
    --data-urlencode "chat_id=\$CHAT_ID" \
    --data-urlencode "text=\$1" \
    "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
    | jq -e '.ok' >/dev/null
}
EOF
chmod +x "$BIN/telegram_notify.sh"

# notifier
cat >"$BIN/postfix-telegram-notify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/bin/telegram_notify.sh

# сколько минут назад смотреть
INTERVAL_MIN=5

# временные метки
NOW=\$(date '+%Y-%m-%d %H:%M:%S')
PAST=\$(date -d "\$INTERVAL_MIN minutes ago" '+%Y-%m-%d %H:%M:%S')

# вытаскиваем нужные строки из journalctl
journalctl -u postfix --since "\$PAST" --until "\$NOW" --no-pager \
  | grep -E 'status=(bounced|deferred)|NOQUEUE: reject:' \
  | while read -r line; do
      send_telegram "\$line"
  done
EOF
chmod +x "$BIN/postfix-telegram-notify.sh"

# systemd service + timer
cat >/etc/systemd/system/postfix-telegram-notify.service <<EOF
[Unit]
Description=Postfix → Telegram notifier (oneshot)

[Service]
Type=oneshot
ExecStart=$BIN/postfix-telegram-notify.sh
EOF

cat >/etc/systemd/system/postfix-telegram-notify.timer <<EOF
[Unit]
Description=Run postfix-telegram-notify every 5 minutes

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now postfix-telegram-notify.timer

echo "✅ Установлено! Проверка каждые $INTERVAL_MIN минут."
echo "   service: postfix-telegram-notify.timer"
