# 📬 Postfix Telegram Notifier

A Bash script to monitor Postfix mail delivery statuses (`sent`, `bounced`, `deferred`) and send real-time notifications to a Telegram chat. The script tracks `/var/log/mail.log`, sends formatted alerts with queue ID, recipient, status, and timestamp, and runs as a systemd service with a configurable timer.

![GitHub License](https://img.shields.io/github/license/{username}/postfix-telegram-notifier)
![GitHub Issues](https://img.shields.io/github/issues/{username}/postfix-telegram-notifier)
![GitHub Stars](https://img.shields.io/github/stars/{username}/postfix-telegram-notifier)

## ✨ Features

- **Real-time Notifications**: Sends Telegram messages for Postfix delivery statuses (`sent`, `bounced`, `deferred`).  
- **Interactive Setup**: Prompts for Telegram Bot Token and Chat ID during installation.  
- **Systemd Integration**: Runs as a systemd service with a timer (default: every 5 minutes).  
- **Log Rotation Handling**: Automatically detects log file rotations to avoid missing events.  
- **Error Logging**: Saves errors to `/var/log/postfix-telegram-notify.log` for debugging.  
- **Robust Parsing**: Safely handles log parsing with fallback values to prevent crashes.  
- **Test Message**: Sends a test notification on installation to verify setup.  

## 📋 Prerequisites

- **OS**: Linux with systemd (e.g., Ubuntu, Debian, CentOS).  
- **Dependencies**:
    - `bash`
    - `curl`
    - `jq`
    - `awk`, `grep`
    - `sudo` privileges  
- **Telegram Bot**:
    - Create a bot via [BotFather](https://t.me/BotFather) to get a Bot Token.
    - Obtain a Chat ID for your Telegram chat.

## 🚀 Installation

1. Clone the repo:  
    ```bash
    git clone https://github.com/Anton-Babaskin/postfix-telegram-notifier.git
    cd postfix-telegram-notifier
    ```
2. Run installer:  
    ```bash
    sudo bash postfix-telegram-notifier.sh
    ```
3. Enter **Bot Token** and **Chat ID** when prompted.  
4. Verify timer:  
    ```bash
    systemctl list-timers postfix-telegram-notify.timer
    ```

## 🔧 Configuration

- **Log File** (default `/var/log/mail.log`):  
    ```bash
    export LOG_FILE=/var/log/maillog
    sudo bash install.sh
    ```
- **Timer Interval**: edit `/etc/systemd/system/postfix-telegram-notify.timer`:
    ```ini
    [Timer]
    OnCalendar=*:0/1  # every minute
    ```
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl restart postfix-telegram-notify.timer
    ```
- **Log Rotation**: handled automatically via inode tracking.

## 📄 Logs

- **Error Logs**: `/var/log/postfix-telegram-notify.log`  
- **State Files**:  
  - `/var/lib/postfix-telegram-notify/lastpos`  
  - `/var/lib/postfix-telegram-notify/lastpos.inode`

**Optional logrotate**:
```bash
sudo tee /etc/logrotate.d/postfix-telegram-notify > /dev/null <<EOF
/var/log/postfix-telegram-notify.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF
```

## 📨 Notification Format

Example Telegram message:
```text
📬 Delivery @ server.example.com
Time: Aug 01 14:30:45
QueueID: 1234567890ABCDEF
To: user@example.com
Status: sent
```
- 🔄 **Log file rotated**: when the log rotates.  
- ⚠️ **Error**: if `/var/log/mail.log` is inaccessible.

## 🛠 Troubleshooting

- **No notifications**:
    - Check Bot Token & Chat ID in `/usr/local/bin/telegram_notify.sh`.
    - Install `curl` & `jq`:
      ```bash
      sudo apt install curl jq   # Debian/Ubuntu
      sudo yum install curl jq   # CentOS
      ```
    - Verify `/var/log/mail.log` exists.
    - Inspect `/var/log/postfix-telegram-notify.log`.
- **"Integer expression expected"**: state files are initialized and validated by the script.
- **Timer not running**:
    ```bash
    systemctl status postfix-telegram-notify.timer
    sudo systemctl restart postfix-telegram-notify.timer
    ```

## 📜 License

Released under the MIT License. See `LICENSE`.

## 🤝 Contributing

1. Fork the repo.  
2. `git checkout -b feature-name`  
3. `git commit -m "Add feature"`  
4. `git push origin feature-name`  
5. Open a PR.

## 📧 Contact

Open an issue or DM on GitHub.

⭐ If this project helps you, drop a ⭐!
