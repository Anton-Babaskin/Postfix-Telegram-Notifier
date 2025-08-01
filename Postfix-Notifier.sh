#!/usr/bin/env bash

set -euo pipefail

# Interactive installer for Postfix delivery status → Telegram notifier

# Check for required tools
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null; then
    echo "Error: $cmd is required but not installed. Please install $cmd."
    exit 1
  fi
done

# Interactive input
read -rp "Enter your Telegram Bot Token: " BOT_TOKEN
if [[ -z "$BOT_TOKEN" ]]; then
  echo "Error: Bot Token cannot be empty."
  exit 1
fi

read -rp "Enter your Telegram Chat ID: " CHAT_ID
if [[ -z "$CHAT_ID" ]]; then
  echo "Error: Chat ID cannot be empty."
  exit 1
fi

# Paths configuration
BIN_DIR=/usr/local/bin
STATE_DIR=/var/lib/postfix-telegram-notify
LOG_DIR=/var/log
ERROR_LOG=${LOG_DIR}/postfix-telegram-notify.log
SERVICE_FILE=/etc/systemd/system/postfix-telegram-notify.service
TIMER_FILE=/etc/systemd/system/postfix-telegram-notify.timer
LOG_FILE=${LOG_FILE:-/var/log/mail.log}

echo "Installing Postfix Telegram notifier…"

# Create state and log directories/files
sudo mkdir -p "$STATE_DIR" "$LOG_DIR"
sudo chmod 755 "$STATE_DIR"
sudo chown root:root "$STATE_DIR"
sudo touch "$ERROR_LOG"
sudo chmod 644 "$ERROR_LOG"
sudo chown root:root "$ERROR_LOG"

# 1) Create Telegram helper script
sudo tee "${BIN_DIR}/telegram_notify.sh" > /dev/null <<EOF
#!/usr/bin/env bash

set -euo pipefail

# Telegram Bot credentials
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

# Send a message via Telegram Bot API
send_telegram() {
  local msg encoded
  msg="\$1"
  encoded=\$(printf '%s' "\$msg" | sed -e 's/%/%25/g' -e 's/&/%26/g' -e 's/#/%23/g')
  curl -fsSL --retry 3 --max-time 10 \\
    -d "chat_id=\$CHAT_ID&text=\$encoded" \\
    "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \\
    | jq -e '.ok' >/dev/null || {
      echo "\$(date): Failed to send message: \$msg" >> ${ERROR_LOG}
      return 1
    }
}
EOF
sudo chmod 755 "${BIN_DIR}/telegram_notify.sh"
sudo chown root:root "${BIN_DIR}/telegram_notify.sh"

# 2) Create main notifier script
sudo tee "${BIN_DIR}/postfix-telegram-notify.sh" > /dev/null <<EOF
#!/usr/bin/env bash

set -euo pipefail

# Load Telegram helper
source ${BIN_DIR}/telegram_notify.sh

LOG_FILE=$LOG_FILE
STATE_FILE=${STATE_DIR}/lastpos
STATE_INODE=${STATE_DIR}/lastpos.inode
ERROR_LOG=${ERROR_LOG}
HOSTNAME=\$(hostname -f)

# Check if log file exists and is readable
if [ ! -r "\$LOG_FILE" ]; then
  send_telegram "⚠️ Error @ \$HOSTNAME: Log file \$LOG_FILE is not readable or does not exist"
  echo "\$(date): Error: Log file \$LOG_FILE is not readable or does not exist" >> "\$ERROR_LOG"
  exit 1
fi

# Initialize state file
mkdir -p "\$(dirname "\$STATE_FILE")"
touch "\$STATE_FILE" "\$STATE_INODE"
chmod 644 "\$STATE_FILE" "\$STATE_INODE"
chown root:root "\$STATE_FILE" "\$STATE_INODE"

# Check for log rotation
last=\$(<"\$STATE_FILE" 2>/dev/null || echo 0)
[[ "\$last" =~ ^[0-9]+$ ]] || last=0
if [ "\$(stat -c %i "\$LOG_FILE" 2>/dev/null)" != "\$(cat "\$STATE_INODE" 2>/dev/null)" ]; then
  send_telegram "🔄 Log file rotated @ \$HOSTNAME"
  last=0
  stat -c %i "\$LOG_FILE" > "\$STATE_INODE"
fi

total=\$(wc -l <"\$LOG_FILE")
[ "\$total" -le "\$last" ] && exit 0

# Parse new log entries for delivery status
tail -n +"\$((last+1))" "\$LOG_FILE" | \\
awk '
  /postfix\\/(smtp|local|lmtp|bounce)/ && /status=(sent|bounced|deferred)/ { print \$0 }
' | while read -r line; do
  id=\$(echo "\$line" | grep -oP '\\b[0-9A-F]{10,}\\b' || echo "N/A")
  to=\$(echo "\$line" | grep -oP 'to=<\\K[^>]+' || echo "N/A")
  status=\$(echo "\$line" | grep -oP 'status=\\K[^ ]+' || echo "N/A")
  timestamp=\$(echo "\$line" | cut -d' ' -f1-3)
  if [ "\$id" != "N/A" ] && [ "\$to" != "N/A" ] && [ "\$status" != "N/A" ]; then
    send_telegram "📬 Delivery @ \$HOSTNAME\nTime: \$timestamp\nQueueID: \$id\nTo: \$to\nStatus: \$status"
  else
    echo "\$(date): Failed to parse log line: \$line" >> "\$ERROR_LOG"
  fi
done

# Update state
echo "\$total" >"\$STATE_FILE"
EOF
sudo chmod 755 "${BIN_DIR}/postfix-telegram-notify.sh"
sudo chown root:root "${BIN_DIR}/postfix-telegram-notify.sh"

# 3) Create systemd service unit
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Postfix Telegram Notify Service

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/postfix-telegram-notify.sh
Environment="LOG_FILE=$LOG_FILE"

[Install]
WantedBy=multi-user.target
EOF
sudo chmod 644 "$SERVICE_FILE"
sudo chown root:root "$SERVICE_FILE"

# 4) Create systemd timer unit
sudo tee "$TIMER_FILE" > /dev/null <<EOF
[Unit]
Description=Run postfix-telegram-notify every 5 minutes

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF
sudo chmod 644 "$TIMER_FILE"
sudo chown root:root "$TIMER_FILE"

# 5) Reload systemd and enable timer
sudo systemctl daemon-reload
sudo systemctl enable --now postfix-telegram-notify.timer

# 6) Test run
echo "Sending test message..."
source "${BIN_DIR}/telegram_notify.sh"
send_telegram "✅ Postfix Telegram Notifier installed successfully on $(hostname -f)" || {
  echo "Error: Test message failed. Please check BOT_TOKEN and CHAT_ID."
  exit 1
}

echo "Installation complete. Timer is active:"
systemctl list-timers postfix-telegram-notify.timer --no-pager
