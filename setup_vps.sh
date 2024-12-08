#!/bin/sh

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then 
    echo "Запустите скрипт от имени root"
    exit 1
fi

# Запрос портов для туннелей
printf "\n\033[1;34m=== Настройка портов туннелей ===\033[0m\n"
printf "Диапазоны портов:\n"
printf "  0-1023: системные порты (не рекомендуется)\n"
printf "  1024-49151: пользовательские порты (рекомендуется)\n"
printf "  49152-65535: динамические порты (для временных соединений)\n"

# Функция проверки портов
check_ports() {
    local ports="$1"
    local has_error=0
    
    for port in $ports; do
        if [ "$port" -lt 1024 ]; then
            printf "\n\033[1;31m✗ Ошибка: Порт %s является системным (0-1023)\033[0m\n" "$port"
            printf "Рекомендуется использовать порты из диапазона 1024-49151\n"
            has_error=1
        elif [ "$port" -gt 49151 ]; then
            printf "\n\033[1;33m⚠ Предупреждение: Порт %s находится в диапазоне динамических портов (49152-65535)\033[0m\n" "$port"
            printf "Рекомендуется использовать пользовательские порты (1024-49151)\n"
            read -p "Продолжить? (1 - да/2 - нет) [2]: " continue_anyway
            if [ "$continue_anyway" != "1" ]; then
                has_error=1
            fi
        fi
    done
    
    return $has_error
}

# Цикл ввода портов
while true; do
    read -p "Введите порты для туннелей через пробел (например: 10022 10080): " TUNNEL_PORTS
    
    if check_ports "$TUNNEL_PORTS"; then
        break
    else
        printf "\n\033[1;33mПожалуйста, введите порты заново.\033[0m\n\n"
    fi
done

# Проверка установленных firewall
printf "\n\033[1;34m=== Проверка firewall ===\033[0m\n"
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

printf "\n\033[1;34m=== Выбор firewall ===\033[0m\n"
printf "\033[1mДоступные опции:\033[0m\n\n"
printf "\033[1m1) UFW - современный firewall, простой в управлении\033[0m\n"
printf "   - Удобный интерфейс командной строки\n"
printf "   - Простое управление правилами\n"
printf "   - Автоматическое сохранение правил\n\n"

printf "\033[1m2) IPTables - классический firewall Linux\033[0m\n"
printf "   - Более гибкая настройка\n"
printf "   - Низкоуровневый контроль\n"
printf "   - Меньше зависимостей\n"

if [ $UFW_INSTALLED -eq 1 ] && [ $IPTABLES_INSTALLED -eq 1 ]; then
    CHOICE_MADE=0
    # Проверяем наличие активных правил
    UFW_RULES=$(ufw status numbered | grep -E "(ALLOW|DENY)" | wc -l)
    IPTABLES_RULES=$(iptables -L INPUT -n --line-numbers | grep -E "ACCEPT|DROP" | wc -l)
    
    if [ $UFW_RULES -gt 0 ] && [ $IPTABLES_RULES -gt 0 ]; then
        printf "\n\033[1;33m⚠ Внимание: Обнаружены правила в обоих firewall!\033[0m\n"
        printf "Это может привести к конфликтам и непредсказуемому поведению.\n\n"
        printf "\033[1mРекомендуемые действия:\033[0m\n"
        printf "1) Использовать UFW (текущие правила IPTables будут очищены)\n"
        printf "2) Использовать IPTables (UFW будет отключен)\n"
        printf "3) Выйти и разобраться с правилами вручную\n\n"
        read -p "Выберите действие (1/2/3): " clean_choice
        
        case $clean_choice in
            1)
                # Создаем директорию для бэкапов если её нет
                backup_dir="/root/firewall_backup"
                mkdir -p "$backup_dir"
                
                # Создаем бэкап с временной меткой
                timestamp=$(date +%Y%m%d_%H%M%S)
                
                printf "\n\033[1;34m→ Создание резервной копии правил IPTables...\033[0m\n"
                iptables-save > "$backup_dir/iptables_backup_$timestamp.rules"
                printf "Backup сохранен в: \033[32m%s\033[0m\n" "$backup_dir/iptables_backup_$timestamp.rules"
                
                printf "\n\033[1;34m→ Очистка правил IPTables...\033[0m\n"
                iptables -F
                iptables -X
                iptables -P INPUT ACCEPT
                iptables -P FORWARD ACCEPT
                iptables -P OUTPUT ACCEPT
                fw_choice=1
                CHOICE_MADE=1
                ;;
            2)
                # Создаем директорию для бэкапов если её нет
                backup_dir="/root/firewall_backup"
                mkdir -p "$backup_dir"
                
                # Создаем бэкап с временной меткой
                timestamp=$(date +%Y%m%d_%H%M%S)
                
                printf "\n\033[1;34m→ Создание резервной копии правил UFW...\033[0m\n"
                ufw status numbered > "$backup_dir/ufw_backup_$timestamp.rules"
                printf "Backup сохранен в: \033[32m%s\033[0m\n" "$backup_dir/ufw_backup_$timestamp.rules"
                
                printf "\n\033[1;34m→ Отключение UFW...\033[0m\n"
                ufw disable
                printf "\n\033[1;34m→ Удаление UFW...\033[0m\n"
                apt remove -y ufw >/dev/null 2>&1
                fw_choice=2
                CHOICE_MADE=1
                ;;
            *)
                printf "\n\033[1;31m✗ Установка прервана.\033[0m\n"
                printf "Пожалуйста, проверьте и очистите правила firewall вручную:\n"
                printf "UFW: ufw status numbered\n"
                printf "IPTables: iptables -L INPUT -n --line-numbers\n"
                printf "\nДля восстановления правил из backup используйте:\n"
                printf "IPTables: iptables-restore < /path/to/backup.rules\n"
                printf "UFW: ufw enable && cat /path/to/backup.rules | while read rule; do ufw \$rule; done\n"
                exit 1
                ;;
        esac
    fi
    
    if [ $CHOICE_MADE -eq 0 ]; then
        printf "\nВыберите firewall для использования:\n"
        printf "1) UFW (рекомендуется, проще в управлении)\n"
        printf "2) IPTables (классический вариант)\n"
        read -p "Введите номер (1/2): " fw_choice
    fi
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
    printf "\nНи один firewall не установлен. Какой установить?\n"
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

# Функция для проверки и установки пакета
install_package() {
    local package=$1
    if ! dpkg -l | grep -q "^ii  $package "; then
        printf "\033[1;32m→ Установка %s...\033[0m\n" "$package"
        apt install -y "$package" >/dev/null 2>&1
    else
        printf "\033[1;32m✓ Пакет %s уже установлен\033[0m\n" "$package"
    fi
}

# Проверка и установки необходимых пакетов
install_package "fail2ban"
install_package "net-tools"

# Настройка SSH
printf "\n\033[1;34m=== Настройка SSH ===\033[0m\n"
printf "\033[1;32m→ Обновление конфигурации SSH...\033[0m\n"

# Функция для удаления дублирующихся строк в файле
cleanup_config() {
    local file="$1"
    if [ -f "$file" ]; then
        printf "\033[1;32m→ Очистка дублирующихся строк в %s...\033[0m\n" "$file"
        # Создаем временный файл
        temp_file=$(mktemp)
        # Оставляем только последнее вхождение каждой строки, сохраняя порядок
        awk '!seen[$0]++' "$file" > "$temp_file"
        # Заменяем оригинальный файл очищенным
        mv "$temp_file" "$file"
    fi
}

# Функция для безопасного добавления параметров SSH
add_ssh_param() {
    local param="$1"
    local value="$2"
    local file="$3"
    if ! grep -q "^$param\s*$value" "$file"; then
        echo "$param $value" >> "$file"
    fi
}

# Очищаем конфиг от дублирующихся строк
cleanup_config "/etc/ssh/sshd_config"

# Добавляем параметры без дублирования
add_ssh_param "GatewayPorts" "yes" "/etc/ssh/sshd_config"
add_ssh_param "AllowTcpForwarding" "yes" "/etc/ssh/sshd_config"
add_ssh_param "ClientAliveInterval" "30" "/etc/ssh/sshd_config"
add_ssh_param "ClientAliveCountMax" "3" "/etc/ssh/sshd_config"

# Перезапуск SSH
printf "\033[1;32m→ Перезапуск SSH сервера...\033[0m\n"
systemctl restart sshd

# Настройка firewall
printf "\n\033[1;34m=== Настройка firewall ===\033[0m\n"
case $fw_choice in
    2)
        # Очищаем все правила перед настройкой
        cleanup_firewall
        
        # Настройка IPTables
        printf "\033[1;32m→ Настройка правил IPTables...\033[0m\n"
        # Базовые правила
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        # SSH и туннели
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        for port in $TUNNEL_PORTS; do
            printf "\033[1;32m→ Открываем порт %s...\033[0m\n" "$port"
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        done
        # Политика по умолчанию
        iptables -P INPUT DROP
        ;;
    *)
        # Очищаем все правила перед настройкой
        cleanup_firewall
        
        # Настройка UFW
        printf "\033[1;32m→ Настройка правил UFW...\033[0m\n"
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp
        for port in $TUNNEL_PORTS; do
            printf "\033[1;32m→ Открываем порт %s...\033[0m\n" "$port"
            ufw allow "$port/tcp"
        done
        yes | ufw enable
        ;;
esac

# Проверка доступности SSH
printf "\n\033[1;34m=== Проверка доступности SSH ===\033[0m\n"
sleep 2  # Даем время на применение правил

if ! nc -zv localhost 22 2>/dev/null; then
    printf "\033[1;31m✗ SSH недоступен! Откат изменений...\033[0m\n"
    cleanup_firewall
    systemctl restart sshd
    exit 1
fi

printf "\033[1;32m✓ SSH доступен\033[0m\n"

# Настройка параметров ядра
printf "\n\033[1;34m=== Настройка параметров ядра ===\033[0m\n"
printf "\033[1;32m→ Очистка дублирующихся параметров...\033[0m\n"

# Создаем временный файл
temp_file=$(mktemp)

# Оставляем только последнее вхождение каждого параметра
awk '!seen[$1]++ { line[++count] = $0 } END { for(i=1;i<=count;i++) print line[i] }' /etc/sysctl.conf > "$temp_file"

# Заменяем оригинальный файл очищенным
mv "$temp_file" /etc/sysctl.conf

# Функция для безопасного добавления параметров
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

printf "Проверка статуса туннелей...\n\n"

# Получаем список портов из конфигурации
PORTS=$(netstat -tlpn | grep ssh | awk '{print $4}' | cut -d: -f2)

if [ -z "$PORTS" ]; then
    printf "Активных SSH туннелей не обнаружено\n"
    logger "No active SSH tunnels found"
    exit 1
fi

printf "Обнаружены порты: %s\n\n" "$PORTS"

# Проверка активных туннелей
FOUND=0
for port in $PORTS; do
    if ! netstat -an | grep "LISTEN" | grep ":$port " > /dev/null; then
        printf "\033[31m✗ Туннель на порту %s не активен\033[0m\n" "$port"
        logger "Reverse tunnel on port $port is down"
    else
        printf "\033[32m✓ Туннель на порту %s активен\033[0m\n" "$port"
        FOUND=$((FOUND + 1))
    fi
done

printf "\nИтого: активно %d из %d туннелей\n" "$FOUND" "$(echo "$PORTS" | wc -w)"
EOF

chmod +x /root/check_tunnels.sh

# Добавление задания в cron
printf "\n\033[1;33m▶ Настройка автоматического мониторинга:\033[0m\n"
printf "Скрипт мониторинга будет проверять состояние туннелей каждые 5 минут\n"
printf "и записывать информацию о проблемах в системный лог\n\n"
read -p "Добавить мониторинг в cron? (y - да/n - нет) [Y/n]: " add_to_cron
add_to_cron=${add_to_cron:-1}

if [ "$add_to_cron" = "y" ] || [ "$add_to_cron" = "Y" ]; then
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
else
    printf "\n\033[1;33m▶ Для ручного мониторинга используйте команду:\033[0m\n"
    printf "  /root/check_tunnels.sh\n\n"
    printf "Для добавления в cron позже:\n"
    printf "1. Выполните: crontab -e\n"
    printf "2. Добавьте строку: */5 * * * * /root/check_tunnels.sh\n"
fi

printf "\n\033[1;32m"
printf "╔════════════════════════════════════════╗\n"
printf "║         Настройка VPS завершена        ║\n"
printf "╚════════════════════════════════════════╝\033[0m\n"

printf "\nОткрытые порты:\n"
case $fw_choice in
    2)
        iptables -L INPUT -n --line-numbers | grep -E "dpt:(22|$TUNNEL_PORTS)" | sed 's/^/  /'
        ;;
    *)
        ufw status numbered | grep ALLOW | sed 's/^/  /'
        ;;
esac

printf "\n\033[1;33m▶ Проверьте настройки:\033[0m\n"
echo "1. SSH конфигурация: /etc/ssh/sshd_config"
case $fw_choice in
    2)
        echo "2. Firewall: iptables -L INPUT -n --line-numbers"
        echo "   Сохраненные правила: cat /etc/iptables/rules.v4"
        ;;
    *)
        echo "2. Firewall: ufw status"
        ;;
esac
echo "3. Скрипт мониторинга: /root/check_tunnels.sh"
echo "4. Cron задания: crontab -l" 
