#!/usr/bin/env bash

set -euo pipefail

# Interactive installer for Postfix delivery status → Telegram notifier

# must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: run installer as root"
  exit 1
fi

# Check for required tools
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null; then
    echo "Error: $cmd is required but not installed. Please install $cmd."
    exit 1
  fi
done

# Interactive input
read -rp "Enter your Telegram Bot Token: " BOT_TOKEN
[[ -n $BOT_TOKEN ]] || { echo "Error: Bot Token cannot be empty."; exit 1; }

read -rp "Enter your Telegram Chat ID: " CHAT_ID
[[ -n $CHAT_ID ]] || { echo "Error: Chat ID cannot be empty."; exit 1; }

# Paths configuration
BIN_DIR=/usr/local/bin
STATE_DIR=/var/lib/postfix-telegram-notify
LOG_DIR=/var/log
ERROR_LOG=${LOG_DIR}/postfix-telegram-notify.log
SERVICE_FILE=/etc/systemd/system/postfix-telegram-notify.service
TIMER_FILE=/etc/systemd/system/postfix-telegram-notify.timer
LOG_FILE=${LOG_FILE:-/var/log/mail.log}

echo "Installing Postfix Telegram notifier…"

# Create needed dirs and files
mkdir -p "$BIN_DIR" "$STATE_DIR" "$LOG_DIR"
chmod 755 "$STATE_DIR"
chown root:root "$STATE_DIR"
: > "$ERROR_LOG"
chmod 644 "$ERROR_LOG"
chown root:root "$ERROR_LOG"

# 1) Telegram helper
cat > "${BIN_DIR}/telegram_notify.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

send_telegram() {
  local msg uri
  msg="\$1"
  uri=\$(jq -sRr @uri <<<"\$msg")
  curl -fsSL --retry 3 --max-time 10 \\
    --data-urlencode "chat_id=\$CHAT_ID" \\
    --data-urlencode "text=\$uri" \\
    "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \\
    | jq -e '.ok' >/dev/null || {
      echo "\$(date): Failed to send message: \$msg" >> "${ERROR_LOG}"
      return 1
    }
}
EOF
chmod 755 "${BIN_DIR}/telegram_notify.sh"
chown root:root "${BIN_DIR}/telegram_notify.sh"

# 2) Main notifier
cat > "${BIN_DIR}/postfix-telegram-notify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/bin/telegram_notify.sh

LOG_FILE=/var/log/mail.log
STATE_FILE=/var/lib/postfix-telegram-notify/lastpos
STATE_INODE=/var/lib/postfix-telegram-notify/lastpos.inode
ERROR_LOG=/var/log/postfix-telegram-notify.log
HOSTNAME=$(hostname -f)

# ensure state files
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE" "$STATE_INODE"

last=$(<"$STATE_FILE" 2>/dev/null || echo 0)
[[ $last =~ ^[0-9]+$ ]] || last=0

# rotation
current_inode=$(stat -c %i "$LOG_FILE" 2>/dev/null)
saved_inode=$(<"$STATE_INODE" 2>/dev/null || echo)
if [[ $current_inode != $saved_inode ]]; then
  send_telegram "🔄 Log file rotated @ $HOSTNAME"
  last=0
  echo "$current_inode" > "$STATE_INODE"
fi

total=$(wc -l <"$LOG_FILE")
(( total <= last )) && exit 0

tail -n +"$((last+1))" "$LOG_FILE" | \
awk '/postfix\/(smtp|local|lmtp|bounce)/ && ( /status=(bounced|deferred)/ || /NOQUEUE: reject:/ ) { print $0 }' | \
while read -r line; do
  timestamp=$(echo "$line" | cut -d' ' -f1-3)
  if [[ $line =~ NOQUEUE:\ reject: ]]; then
    to=$(echo "$line" | grep -oP 'to=<\K[^>]+' || echo "N/A")
    reason=$(echo "$line" | sed -n 's/.*reject: \(.*\)/\1/p' || echo "N/A")
    send_telegram "⛔ Rejected @ $HOSTNAME\nTime: $timestamp\nTo: $to\nReason: $reason"
  else
    id=$(echo "$line"   | grep -oP '\b[0-9A-F]{10,}\b' || echo "N/A")
    to=$(echo "$line"   | grep -oP 'to=<\K[^>]+'      || echo "N/A")
    status=$(echo "$line"| grep -oP 'status=\K[^ ]+'   || echo "N/A")
    send_telegram "⚠️ Delivery issue @ $HOSTNAME\nTime: $timestamp\nQueueID: $id\nTo: $to\nStatus: $status"
  fi
done

echo "$total" > "$STATE_FILE"
EOF
chmod 755 "${BIN_DIR}/postfix-telegram-notify.sh"
chown root:root "${BIN_DIR}/postfix-telegram-notify.sh"

# 3) systemd service
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Postfix Telegram Notify Service

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/postfix-telegram-notify.sh

[Install]
WantedBy=multi-user.target
EOF

# 4) systemd timer
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run postfix-telegram-notify every 5 minutes

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

# reload and enable
systemctl daemon-reload
systemctl enable --now postfix-telegram-notify.timer

# test
echo "Sending test message..."
source "${BIN_DIR}/telegram_notify.sh"
send_telegram "✅ Postfix Telegram Notifier installed on $(hostname -f)"
echo "Done. Timer is active:"
systemctl list-timers postfix-telegram-notify.timer --no-pager
