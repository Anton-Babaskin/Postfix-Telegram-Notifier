# 📬 Postfix Telegram Notifier

A simple Bash daemon to monitor Postfix delivery failures (`bounced`, `deferred`, `reject`) in real time and send alerts to your Telegram chat. It tails `/var/log/mail.log` with `tail -F`, filters only failed deliveries, and pushes formatted notifications via the Bot API.

![GitHub License](https://img.shields.io/github/license/{username}/postfix-telegram-notifier)  
![GitHub Issues](https://img.shields.io/github/issues/{username}/postfix-telegram-notifier)  
![GitHub Stars](https://img.shields.io/github/stars/{username}/postfix-telegram-notifier)

---

## ✨ Features

- **Real-time alerts** for `bounced` / `deferred` / `reject` events only  
- **Lightweight daemon** via `tail -F` + `systemd` (no state files)  
- **Interactive installer** prompts for Bot Token & Chat ID  
- **Clean helper** script (`telegram_notify.sh`) for Telegram API calls  
- **Automatic restart** under `systemd` on failure  
- **Test message** on install to confirm setup  

---

## 📋 Prerequisites

- **OS**: any Linux with `systemd`  
- **Tools**: `bash`, `curl`, `jq`, `systemctl`  
- **Telegram Bot**:  
    1. Create via [BotFather](https://t.me/BotFather) → get **Bot Token**  
    2. Retrieve your **Chat ID**  

---

## 🚀 Quick Install

    sudo git clone https://github.com/Anton-Babaskin/postfix-telegram-notifier.git /opt/postfix-telegram-notifier \
      || (cd /opt/postfix-telegram-notifier && sudo git pull)
    cd /opt/postfix-telegram-notifier
    sudo bash install.sh

You will be prompted for your **Bot Token** and **Chat ID**. A test alert (“✅ Helper test OK”) will arrive in Telegram.

Verify the daemon:

    systemctl status postfix-telegram-notify.service

---

## 🛠 Usage & Testing

- **Manual test**:

    sudo bash -c 'printf "%s %s postfix/smtp[99999]: TEST_OK: to=<you@domain.com>, status=deferred (TEST)\n" \
      "$(date "+%b %e %H:%M:%S")" "$(hostname -f)" \
      >> /var/log/mail.log'

  → you should receive a “⚠️ Delivery issue … TEST_OK” alert.

- **Live logs**:

    journalctl -u postfix-telegram-notify.service -f

---

## 📝 Customization

- **Log path**  
  Edit the `LOG=/var/log/mail.log` line in `/usr/local/bin/postfix-telegram-notify.sh` if your mail log is elsewhere.

- **Filter logic**  
  Adjust the `if [[ … ]]` test in the script to catch other Postfix patterns.

---

## 📜 License

MIT License — see [LICENSE](LICENSE).

---

## 🤝 Contributing

1. Fork & clone  
2. Create a branch: `git checkout -b feature-name`  
3. Commit & push  
4. Open a pull request  

⭐ If this tool helps you, please give it a star!  
