📬 Postfix Telegram Notifier

A Bash script to monitor Postfix mail delivery statuses (sent, bounced, deferred) and send real-time notifications to a Telegram chat. The script tracks /var/log/mail.log, sends formatted alerts with queue ID, recipient, status, and timestamp, and runs as a systemd service with a configurable timer.











✨ Features





Real-time Notifications: Sends Telegram messages for Postfix delivery statuses (sent, bounced, deferred).



Interactive Setup: Prompts for Telegram Bot Token and Chat ID during installation.



Systemd Integration: Runs as a systemd service with a timer (default: every 5 minutes).



Log Rotation Handling: Automatically detects log file rotations to avoid missing events.



Error Logging: Saves errors to /var/log/postfix-telegram-notify.log for debugging.



Robust Parsing: Safely handles log parsing with fallback values to prevent crashes.



Test Message: Sends a test notification on installation to verify setup.

📋 Prerequisites





Operating System: Linux with systemd (e.g., Ubuntu, Debian, CentOS).



Dependencies:





bash



curl (for Telegram API requests)



jq (for JSON parsing)



awk, grep (for log parsing)



sudo privileges for installation



Telegram Bot:





Create a bot via BotFather to get a Bot Token.



Obtain a Chat ID for your Telegram chat (can be a group or personal chat).

🚀 Installation





Clone the repository:

git clone https://github.com/username/postfix-telegram-notifier.git
cd postfix-telegram-notifier



Run the installer:

sudo bash install.sh



Follow the prompts to enter:





Your Telegram Bot Token.



Your Telegram Chat ID.



The script will:





Install scripts to /usr/local/bin.



Create state files in /var/lib/postfix-telegram-notify.



Set up a systemd service and timer.



Send a test Telegram message to confirm setup.



Verify the timer is active:

systemctl list-timers postfix-telegram-notify.timer

🔧 Configuration





Log File: By default, the script monitors /var/log/mail.log. To use a different log file, set the LOG_FILE environment variable before running the script:

export LOG_FILE=/var/log/maillog
sudo bash install.sh



Timer Interval: The default interval is 5 minutes. To change it, edit /etc/systemd/system/postfix-telegram-notify.timer:

[Timer]
OnCalendar=*:0/1  # Run every 1 minute

Then reload systemd:

sudo systemctl daemon-reload
sudo systemctl restart postfix-telegram-notify.timer



Log Rotation: The script handles log rotations automatically by tracking the log file's inode. No additional configuration is needed.

📄 Logs





Error Logs: Errors (e.g., failed Telegram messages or log parsing issues) are written to /var/log/postfix-telegram-notify.log.



State Files: The last processed log position and inode are stored in /var/lib/postfix-telegram-notify/lastpos and /var/lib/postfix-telegram-notify/lastpos.inode.

To enable rotation for the error log, add a logrotate configuration:

sudo tee /etc/logrotate.d/postfix-telegram-notify > /dev/null <<EOF
/var/log/postfix-telegram-notify.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF

📨 Notification Format

Example Telegram notification:

📬 Delivery @ server.example.com
Time: Aug 01 14:30:45
QueueID: 1234567890ABCDEF
To: user@example.com
Status: sent

Additional notifications:





🔄 Log file rotated @ server.example.com: Sent when the log file is rotated.



⚠️ Error @ server.example.com: Log file /var/log/mail.log is not readable or does not exist: Sent if the log file is inaccessible.

🛠 Troubleshooting





No notifications received:





Check the Telegram Bot Token and Chat ID in /usr/local/bin/telegram_notify.sh.



Verify that curl and jq are installed: sudo apt install curl jq (Debian/Ubuntu) or sudo yum install curl jq (CentOS).



Ensure the log file (/var/log/mail.log) exists and contains Postfix entries.



Inspect /var/log/postfix-telegram-notify.log for errors.



"Integer expression expected" error:





The script includes guards to prevent this by initializing state files and validating the lastpos value.



Timer not running:





Check the timer status: systemctl status postfix-telegram-notify.timer.



Restart the timer: sudo systemctl restart postfix-telegram-notify.timer.

📜 License

This project is licensed under the MIT License. See the LICENSE file for details.

🤝 Contributing

Contributions are welcome! Please:





Fork the repository.



Create a feature branch: git checkout -b feature-name.



Commit your changes: git commit -m "Add feature".



Push to the branch: git push origin feature-name.



Open a pull request.

📧 Contact

For questions or suggestions, open an issue or contact me via GitHub.



⭐ If you find this project useful, please give it a star on GitHub!
