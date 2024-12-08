#!/bin/sh

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then 
    echo "Запустите скрипт от имени root"
    exit 1
fi

# Запрос портов для туннелей
printf "\n\033[1;34m=== Настройка портов туннелей ===\033[0m\n"
read -p "Введите порты для туннелей через пробел (например: 19999 20000): " TUNNEL_PORTS

# Проверка установленных файерволов
printf "\n\033[1;34m=== Проверка файерволов ===\033[0m\n"
printf "Сканирование системы...\n"
UFW_INSTALLED=0
IPTABLES_INSTALLED=0
UFW_ACTIVE=0

if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status | grep -q "Status: active" && echo "активен" || echo "неактивен")
    UFW_INSTALLED=1
    if [ "$UFW_STATUS" = "активен" ]; then
        UFW_ACTIVE=1
    fi
    printf "\n\033[1;32m→ UFW установлен и %s\033[0m\n" "$UFW_STATUS"
    printf "\033[1mТекущие правила UFW:\033[0m\n"
    ufw status numbered | grep -E "(22|$TUNNEL_PORTS)" | sed 's/^/  /'
fi

if command -v iptables >/dev/null 2>&1; then
    IPTABLES_RULES=$(iptables -L INPUT -n --line-numbers | grep -E "dpt:(22|$TUNNEL_PORTS)" | wc -l)
    IPTABLES_INSTALLED=1
    printf "\n\033[1;32m→ IPTables установлен, найдено правил: %s\033[0m\n" "$IPTABLES_RULES"
    printf "\033[1mТекущие правила IPTables:\033[0m\n"
    iptables -L INPUT -n --line-numbers | grep -E "dpt:(22|$TUNNEL_PORTS)" | sed 's/^/  /'
fi

# Предупреждение о конфликтах
if [ $UFW_ACTIVE -eq 1 ] && [ "$fw_choice" = "2" ]; then
    printf "\n\033[1;33m⚠ Внимание: Обнаружен конфликт!\033[0m\n"
    printf "\033[33mUFW активен и управляет правилами iptables!\033[0m\n"
    printf "Использование iptables напрямую может привести к конфликтам.\n\n"
    printf "\033[1mРекомендуемые действия:\033[0m\n"
    printf "1. Отключить UFW: sudo ufw disable\n"
    printf "2. Удалить UFW: sudo apt remove ufw\n"
    printf "3. Продолжить установку\n\n"
    
    printf "\033[1mВыберите действие:\033[0m\n"
    read -p "Отключить UFW перед продолжением? [Y/n]: " disable_ufw
    if [ "$disable_ufw" != "n" ] && [ "$disable_ufw" != "N" ]; then
        printf "\n\033[1;34m→ Отключение UFW...\033[0m\n"
        ufw disable
        printf "\033[1;34m→ Удаление UFW...\033[0m\n"
        apt remove -y ufw
    else
        printf "\n\033[1;33m⚠ Предупреждение: Продолжение с активным UFW может привести к проблемам!\033[0m\n"
        read -p "Продолжить? [y/N]: " continue_anyway
        if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
            printf "\n\033[1;31m✗ Установка прервана.\033[0m\n"
            exit 1
        fi
    fi
fi

printf "\n\033[1;34m=== Выбор файервола ===\033[0m\n"
printf "\033[1mДоступные опции:\033[0m\n\n"
printf "\033[1m1) UFW - современный файервол, простой в управлении\033[0m\n"
printf "   - Удобный интерфейс командной строки\n"
printf "   - Простое управление правилами\n"
printf "   - Автоматическое сохранение правил\n\n"

printf "\033[1m2) IPTables - классический файервол Linux\033[0m\n"
printf "   - Более гибкая настройка\n"
printf "   - Низкоуровневый контроль\n"
printf "   - Меньше зависимостей\n"

if [ $UFW_INSTALLED -eq 1 ] && [ $IPTABLES_INSTALLED -eq 1 ]; then
    printf "\nВыберите файервол для использования:\n"
    printf "1) UFW (рекомендуется, проще в управлении)\n"
    printf "2) IPTables (классический вариант)\n"
    read -p "Введите номер (1/2): " fw_choice
elif [ $UFW_INSTALLED -eq 1 ]; then
    printf "\nUFW уже установлен. Использовать его? [Y/n]: "
    read -r use_ufw
    if [ "$use_ufw" = "n" ] || [ "$use_ufw" = "N" ]; then
        printf "Установка IPTables...\n"
        apt install -y iptables-persistent
        fw_choice=2
    else
        fw_choice=1
    fi
elif [ $IPTABLES_INSTALLED -eq 1 ]; then
    printf "\nIPTables уже установлен. Использовать его? [Y/n]: "
    read -r use_iptables
    if [ "$use_iptables" = "n" ] || [ "$use_iptables" = "N" ]; then
        printf "Установка UFW...\n"
        apt install -y ufw
        fw_choice=1
    else
        fw_choice=2
    fi
else
    printf "\nНи один файервол не установлен. Какой установить?\n"
    printf "1) UFW\n"
    printf "2) IPTables\n"
    read -p "Введите номер (1/2) [1]: " fw_choice
    fw_choice=${fw_choice:-1}
    
    case $fw_choice in
        2)
            printf "Установка IPTables...\n"
            apt install -y iptables-persistent
            ;;
        *)
            printf "Установка UFW...\n"
            apt install -y ufw
            ;;
    esac
fi

# Установка необходимых пакетов
apt update
apt install -y fail2ban net-tools

# Настройка SSH
printf "\nНастройка SSH...\n"
cat >> /etc/ssh/sshd_config << EOF
GatewayPorts yes
AllowTcpForwarding yes
ClientAliveInterval 30
ClientAliveCountMax 3
EOF

# Перезапуск SSH
systemctl restart sshd

# Настройка файервола
printf "\nНастройка файервола...\n"
case $fw_choice in
    2)
        # Настройка IPTables
        # Очистка существующих правил для SSH и туннелей
        for port in 22 $TUNNEL_PORTS; do
            iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        done
        
        # Добавление новых правил
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        for port in $TUNNEL_PORTS; do
            printf "Открываем порт %s...\n" "$port"
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        done
        
        # Сохранение правил
        if [ -x "$(command -v iptables-save)" ]; then
            iptables-save > /etc/iptables/rules.v4
        else
            apt install -y iptables-persistent
            iptables-save > /etc/iptables/rules.v4
        fi
        ;;
    *)
        # Настройка UFW
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp
        
        for port in $TUNNEL_PORTS; do
            printf "Открываем порт %s...\n" "$port"
            ufw allow "$port/tcp"
        done
        
        yes | ufw enable
        ;;
esac

# Настройка системных лимитов
printf "\nНастройка системных лимитов...\n"
cat >> /etc/security/limits.conf << EOF
*               soft    nofile          65535
*               hard    nofile          65535
EOF

cat >> /etc/sysctl.conf << EOF
net.ipv4.ip_forward=1
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
EOF

sysctl -p

# Создание скрипта мониторинга
printf "\nСоздание скрипта мониторинга туннелей...\n"
cat > /root/check_tunnels.sh << 'EOF'
#!/bin/sh

# Получаем список портов из конфигурации
PORTS=$(netstat -tlpn | grep autossh | awk '{print $4}' | cut -d: -f2)

# Проверка активных туннелей
for port in $PORTS; do
    if ! netstat -an | grep "LISTEN" | grep ":$port " > /dev/null; then
        echo "Туннель на порту $port не активен"
        logger "Reverse tunnel on port $port is down"
    fi
done
EOF

chmod +x /root/check_tunnels.sh

# Добавление задания в cron
printf "\nДобавление задания мониторинга в cron...\n"
(crontab -l 2>/dev/null; echo "*/5 * * * * /root/check_tunnels.sh") | crontab -

# Настройка fail2ban
printf "\nНастройка fail2ban...\n"
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

systemctl restart fail2ban

echo "Настройка VPS завершена"
printf "\nОткрытые порты:\n"
ufw status numbered | grep ALLOW

printf "\nПроверьте настройки:\n"
echo "1. SSH конфигурация: /etc/ssh/sshd_config"
echo "2. Файервол: iptables -L INPUT -n --line-numbers"
echo "   Сохраненные правила: cat /etc/iptables/rules.v4"
echo "3. Fail2ban: fail2ban-client status"
echo "4. Скрипт мониторинга: /root/check_tunnels.sh"
echo "5. Cron задания: crontab -l" 
