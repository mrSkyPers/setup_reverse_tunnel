#!/bin/sh

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then 
    echo "Запустите скрипт от имени root"
    exit 1
fi

printf "\n\033[1;34m=== Настройка защиты от брутфорса ===\033[0m\n"

# Проверка и установка fail2ban
if ! command -v fail2ban-client >/dev/null 2>&1; then
    printf "\033[1;32m→ Установка fail2ban...\033[0m\n"
    apt update
    apt install -y fail2ban
else
    printf "\033[1;32m✓ fail2ban уже установлен\033[0m\n"
fi

# Создание конфигурации
printf "\033[1;32m→ Настройка конфигурации...\033[0m\n"
cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 300
bantime = 3600
EOF

# Перезапуск службы
printf "\033[1;32m→ Перезапуск службы...\033[0m\n"
systemctl restart fail2ban

# Проверка статуса
printf "\n\033[1;32m✓ Настройка fail2ban завершена\033[0m\n"
printf "\nСтатус защиты:\n"
fail2ban-client status sshd | sed 's/^/  /'

printf "\n\033[1;33m▶ Полезные команды:\033[0m\n"
printf "Просмотр статуса:    \033[32mfail2ban-client status sshd\033[0m\n"
printf "Просмотр логов:      \033[32mtail -f /var/log/fail2ban.log\033[0m\n"
printf "Список заблокированных IP: \033[32mfail2ban-client get sshd banip\033[0m\n"
printf "Разблокировать IP:   \033[32mfail2ban-client set sshd unbanip IP\033[0m\n" 