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

# Предупреждение о конфликтах
if [ $UFW_ACTIVE -eq 1 ] && [ "$fw_choice" = "2" ]; then
    printf "\n\033[1;33m⚠ Внимание: Обнаружен конфликт!\033[0m\n"
    printf "\033[33mUFW активен и управляет правилами iptables!\033[0m\n"
    printf "Использование iptables напрямую может привести к конфликтам.\n\n"
    
    printf "\033[1mВыберите действие:\033[0m\n"
    printf "1) Только отключить UFW\n"
    printf "2) Отключить и удалить UFW\n"
    printf "3) Продолжить с активным UFW\n"
    read -p "Выберите действие (1/2/3): " disable_ufw
    if [ "$disable_ufw" = "1" ]; then
        printf "\n\033[1;34m→ Отключение UFW...\033[0m\n"
        ufw disable
    elif [ "$disable_ufw" = "2" ]; then
        printf "\n\033[1;34m→ Отключение UFW...\033[0m\n"
        ufw disable
        printf "\n\033[1;34m→ Удаление UFW...\033[0m\n"
        apt remove -y ufw
    else
        printf "\n\033[1;33m⚠ Предупреждение: Продолжение с активным UFW может привести к проблемам!\033[0m\n"
        read -p "Продолжить? (1 - да/2 - нет) [2]: " continue_anyway
        if [ "$continue_anyway" != "1" ]; then
            printf "\n\033[1;31m✗ Установка прервана.\033[0m\n"
            exit 1
        fi
    fi
fi

# Установка необходимых пакетов
printf "\n\033[1;34m=== Установка дополнительных пакетов ===\033[0m\n"
apt update
apt install -y fail2ban net-tools

# Настройка SSH
printf "\n\033[1;34m=== Настройка SSH ===\033[0m\n"
printf "\033[1;32m→ Обновление конфигурации SSH...\033[0m\n"
cat >> /etc/ssh/sshd_config << EOF
GatewayPorts yes
AllowTcpForwarding yes
ClientAliveInterval 30
ClientAliveCountMax 3
EOF

# Перезапуск SSH
printf "\033[1;32m→ Перезапуск SSH сервера...\033[0m\n"
systemctl restart sshd

# Настройка файервола
printf "\n\033[1;34m=== Настройка файервола ===\033[0m\n"
case $fw_choice in
    2)
        # Настройка IPTables
        # Очистка существующих правил для SSH и туннелей
        printf "\033[1;32m→ Настройка правил IPTables...\033[0m\n"
        for port in 22 $TUNNEL_PORTS; do
            iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        done
        
        # Добавление новых правил
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        for port in $TUNNEL_PORTS; do
            printf "\033[1;32m→ Открываем порт %s...\033[0m\n" "$port"
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        done
        
        # Сохранение правил
        printf "\033[1;32m→ Сохранение правил IPTables...\033[0m\n"
        mkdir -p /etc/iptables
        if [ -x "$(command -v iptables-save)" ]; then
            iptables-save > /etc/iptables/rules.v4
        else
            apt install -y iptables-persistent
            iptables-save > /etc/iptables/rules.v4
        fi
        ;;
    *)
        # Настройка UFW
        printf "\033[1;32m→ Настройка правил UFW...\033[0m\n"
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp
        
        for port in $TUNNEL_PORTS; do
            printf "\033[1;32m→ Открываем порт %s...\033[0m\n" "$port"
            ufw allow "$port/tcp"
        done
        
        printf "\033[1;32m→ Активация UFW...\033[0m\n"
        yes | ufw enable
        ;;
esac

# Настройка системных лимитов
printf "\n\033[1;34m=== Настройка системных лимитов ===\033[0m\n"
printf "\033[1;32m→ Установка лимитов файловых дескрипторов...\033[0m\n"
cat >> /etc/security/limits.conf << EOF
*               soft    nofile          65535
*               hard    nofile          65535
EOF

# Настройка параметров ядра
printf "\n\033[1;34m=== Настройка параметров ядра ===\033[0m\n"
printf "\033[1;32m→ Очистка дублирующихся параметров...\033[0m\n"

# Создаем временный файл
temp_file=$(mktemp)

# Оставляем только последнее вхождение каждого параметра
awk '!seen[$1]++ { line[++count] = $0 } END { for(i=1;i<=count;i++) print line[i] }' /etc/sysctl.conf > "$temp_file"

# Заменяем оригинальный файл очищенным
mv "$temp_file" /etc/sysctl.conf

# Функция для безопасного добавл��ния параметров
add_sysctl_param() {
    param=$1
    value=$2
    if ! grep -q "^$param\s*=" /etc/sysctl.conf; then
        echo "$param=$value" >> /etc/sysctl.conf
    fi
}

# Добавляем параметры только если их нет
add_sysctl_param "net.ipv4.ip_forward" "1"
add_sysctl_param "net.ipv4.tcp_max_syn_backlog" "65535"

# Применяем изменения
sysctl -p 2>/dev/null || true

# Создание скрипта мониторинга
printf "\n\033[1;34m=== Настройка мониторинга ===\033[0m\n"
printf "\033[1;32m→ Создание скрипта мониторинга...\033[0m\n"
cat > /root/check_tunnels.sh << 'EOF'
#!/bin/sh

# Получаем список портов из конфигурации
PORTS=$(netstat -tlpn | grep ssh | awk '{print $4}' | cut -d: -f2)

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
printf "\033[1;32m→ Добавление задания в cron...\033[0m\n"

# Создаем временный файл
temp_cron=$(mktemp)

# Получаем текущие задания и добавляем новое
(crontab -l 2>/dev/null; echo "*/5 * * * * /root/check_tunnels.sh") | \
    # Удаляем пустые строки и комментарии
    grep -v '^#\|^$' | \
    # Сортируем и оставляем только уникальные строки
    sort -u > "$temp_cron"

# Устанавливаем обновленный crontab
crontab "$temp_cron"

# Удаляем временный файл
rm -f "$temp_cron"

printf "\033[1;32m→ Текущие задания в cron:\033[0m\n"
crontab -l | grep -v '^#\|^$' | sed 's/^/  /'

# Настройка fail2ban
printf "\n\033[1;34m=== Настройка защиты от брутфорса ===\033[0m\n"
printf "\033[1;32m→ Настройка fail2ban...\033[0m\n"
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

printf "\n\033[1;34m=== Настройка VPS завершена ===\033[0m\n"
printf "\nОткрытые порты:\n"
case $fw_choice in
    2)
        iptables -L INPUT -n --line-numbers | grep -E "dpt:(22|$TUNNEL_PORTS)" | sed 's/^/  /'
        ;;
    *)
        ufw status numbered | grep ALLOW | sed 's/^/  /'
        ;;
esac

printf "\n\033[1;33mПроверьте настройки:\033[0m\n"
echo "1. SSH конфигурация: /etc/ssh/sshd_config"
case $fw_choice in
    2)
        echo "2. Файервол: iptables -L INPUT -n --line-numbers"
        echo "   Сохраненные правила: cat /etc/iptables/rules.v4"
        ;;
    *)
        echo "2. Файервол: ufw status"
        ;;
esac
echo "3. Fail2ban: fail2ban-client status"
echo "4. Скрипт мониторинга: /root/check_tunnels.sh"
echo "5. Cron задания: crontab -l" 
