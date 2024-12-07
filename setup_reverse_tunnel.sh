#!/bin/bash

# Установка цветов для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Настройка обратного SSH-туннеля для OpenWRT${NC}\n"

# Выбор SSH сервера
echo -e "${YELLOW}Выберите SSH сервер:${NC}"
echo "1) OpenSSH (рекомендуется)"
echo "2) Dropbear (установлен по умолчанию, меньше нагрузки на сервер)"
read -p "Введите номер (1/2): " ssh_choice

case $ssh_choice in
    2)
        if ! command -v dropbear &> /dev/null; then
            echo -e "\n${GREEN}Установка Dropbear...${NC}"
            opkg update
            opkg install dropbear
            /etc/init.d/dropbear enable
            /etc/init.d/dropbear start
        else
            echo -e "\n${GREEN}Dropbear уже установлен${NC}"
        fi
        ;;
    *)
        if ! command -v ssh &> /dev/null; then
            echo -e "\n${GREEN}Установка OpenSSH...${NC}"
            opkg update
            opkg install openssh-server openssh-sftp-server
            /etc/init.d/sshd enable
            /etc/init.d/sshd start
        else
            echo -e "\n${GREEN}OpenSSH уже установлен${NC}"
        fi
        ;;
esac

# Установка sshpass для автоматического ввода пароля
if ! command -v sshpass &> /dev/null; then
    echo -e "\n${GREEN}Установка sshpass...${NC}"
    opkg update
    opkg install sshpass
else
    echo -e "\n${GREEN}sshpass уже установлен${NC}"
fi

# Запрос данных VPS
if [ -f /etc/config/reverse-tunnel ]; then
    echo -e "\n${YELLOW}Обнаружена существующая конфигурация туннеля.${NC}"
    read -p "Хотите использовать существующую конфигурацию? (y/N): " use_existing
    if [[ $use_existing =~ ^[Yy]$ ]]; then
        vps_ip=$(uci get reverse-tunnel.@general[0].vps_ip)
        vps_user=$(uci get reverse-tunnel.@general[0].vps_user)
        ssh_port=$(uci get reverse-tunnel.@general[0].ssh_port)
        echo -e "Загружена конфигурация:"
        echo -e "VPS IP: ${vps_ip}"
        echo -e "Пользователь: ${vps_user}"
        echo -e "SSH порт: ${ssh_port}"
    else
        echo -e "\n${YELLOW}Создание новой конфигурации...${NC}"
        mv /etc/config/reverse-tunnel /etc/config/reverse-tunnel.backup
        echo -e "Предыдущая конфигурация сохранена как /etc/config/reverse-tunnel.backup"
    fi
fi

if [[ ! $use_existing =~ ^[Yy]$ ]]; then
    read -p "Введите IP-адрес VPS сервера: " vps_ip
    read -p "Введите имя пользователя на VPS: " vps_user
    read -p "Введите порт для SSH на VPS (по умолчанию 22): " ssh_port
    ssh_port=${ssh_port:-22}
    read -s -p "Введите пароль пользователя на VPS: " vps_password
    echo ""
fi

# Массив для хранения туннелей
declare -a tunnel_ports
declare -a local_ports
declare -a local_hosts

# Запрос количества туннелей
read -p "Сколько туннелей вы хотите настроить? " tunnel_count

for ((i=1; i<=tunnel_count; i++)); do
    echo -e "\n${YELLOW}Настройка туннеля $i:${NC}"
    read -p "Введите удаленный порт для туннеля $i (например 19999): " remote_port
    read -p "Введите локальный порт для туннеля $i (например 22): " local_port
    read -p "Введите IP-адрес локального устройства (нажмите Enter для localhost): " local_host
    local_host=${local_host:-localhost}
    tunnel_ports+=($remote_port)
    local_ports+=($local_port)
    local_hosts+=($local_host)
done

# Создание SSH-ключей
echo -e "\n${GREEN}Генерация SSH-ключей...${NC}"
if [ "$ssh_choice" = "2" ]; then
    # Использование dropbearkey для Dropbear
    if [ ! -f /root/.ssh/id_rsa ]; then
        mkdir -p /root/.ssh
        dropbearkey -t rsa -f /root/.ssh/id_rsa
        # Конвертация публичного ключа в формат OpenSSH
        dropbearkey -y -f /root/.ssh/id_rsa | grep "^ssh-rsa" > /root/.ssh/id_rsa.pub
    fi
else
    # Использование ssh-keygen для OpenSSH
    if [ ! -f /root/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
    fi
fi

# Копирование публичного ключа на VPS
echo -e "\n${GREEN}Копирование публичного ключа на VPS...${NC}"
if [ "$ssh_choice" = "2" ]; then
    # Для Dropbear используем cat и ssh для копирования ключа
    KEY=$(cat /root/.ssh/id_rsa.pub)
    sshpass -p "$vps_password" ssh -o StrictHostKeyChecking=no -p $ssh_port "${vps_user}@${vps_ip}" "mkdir -p ~/.ssh && echo '$KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
else
    # Для OpenSSH используем ssh-copy-id
    sshpass -p "$vps_password" ssh-copy-id -o StrictHostKeyChecking=no -p $ssh_port "${vps_user}@${vps_ip}"
fi

# Создание скрипта автозапуска
cat > /etc/init.d/reverse-tunnel << EOF
#!/bin/sh /etc/rc.common

START=99
STOP=15
USE_PROCD=1

PROG=/usr/bin/autossh
CONFIGFILE=/etc/config/reverse-tunnel

start_service() {
    config_load reverse-tunnel
    
    procd_open_instance
    procd_set_param command \$PROG -M 0 -N \\
EOF

# Добавление всех туннелей в команду
for ((i=0; i<${#tunnel_ports[@]}; i++)); do
    echo "        -R ${tunnel_ports[i]}:${local_hosts[i]}:${local_ports[i]} \\" >> /etc/init.d/reverse-tunnel
done

cat >> /etc/init.d/reverse-tunnel << EOF
        ${vps_user}@${vps_ip} -p ${ssh_port}
    
    procd_set_param respawn 3600 5 0
    procd_set_param stderr 1
    procd_set_param stdout 1
    procd_close_instance
}

service_triggers() {
    procd_add_reload_trigger "reverse-tunnel"
}

reload_service() {
    stop
    start
}
EOF

# Создание конфигурационного файла
mkdir -p /etc/config
cat > /etc/config/reverse-tunnel << EOF
config reverse-tunnel 'general'
    option enabled '1'
    option ssh_port '${ssh_port}'
    option vps_user '${vps_user}'
    option vps_ip '${vps_ip}'
EOF

# Добавление туннелей в конфиг
for ((i=0; i<${#tunnel_ports[@]}; i++)); do
    cat >> /etc/config/reverse-tunnel << EOF
config tunnel
    option remote_port '${tunnel_ports[i]}'
    option local_port '${local_ports[i]}'
    option local_host '${local_hosts[i]}'
EOF
done

# Установка прав и включение автозапуска
chmod +x /etc/init.d/reverse-tunnel
/etc/init.d/reverse-tunnel enable
/etc/init.d/reverse-tunnel start

# Установка autossh если не установлен
if ! command -v autossh &> /dev/null; then
    echo -e "\n${GREEN}Установка autossh...${NC}"
    opkg update
    opkg install autossh
else
    echo -e "\n${GREEN}autossh уже установлен${NC}"
fi

echo -e "\n${GREEN}Настройка завершена!${NC}"
echo -e "Для подключения к OpenWRT используйте следующие команды на вашем VPS сервере:"

for ((i=0; i<${#tunnel_ports[@]}; i++)); do
    echo -e "Туннель $((i+1)): ssh -p ${tunnel_ports[i]} root@localhost (-> ${local_hosts[i]}:${local_ports[i]})"
done

echo -e "\n${YELLOW}Созданные файлы и конфигурации:${NC}"
echo -e "\n1. Основные конфигурационные файлы:"
echo -e "   - Конфигурация туннелей: ${GREEN}/etc/config/reverse-tunnel${NC}"
echo -e "   - Скрипт автозапуска: ${GREEN}/etc/init.d/reverse-tunnel${NC}"

echo -e "\n2. SSH конфигурация:"
if [ "$ssh_choice" = "2" ]; then
    echo -e "   - Конфигурация Dropbear: ${GREEN}/etc/config/dropbear${NC}"
else
    echo -e "   - Конфигурация OpenSSH: ${GREEN}/etc/config/sshd${NC}"
fi
echo -e "   - SSH ключи: ${GREEN}/root/.ssh/id_rsa${NC} (приватный) и ${GREEN}/root/.ssh/id_rsa.pub${NC} (публичный)"
echo -e "   - Настройки SSH клиента: ${GREEN}/etc/ssh/ssh_config${NC}"

echo -e "\n3. Настройки AutoSSH:"
echo -e "   - Конфигурация AutoSSH: ${GREEN}/etc/default/autossh${NC}"

echo -e "\n${YELLOW}Управление службой:${NC}"
echo -e "Запуск:          ${GREEN}/etc/init.d/reverse-tunnel start${NC}"
echo -e "Остановка:       ${GREEN}/etc/init.d/reverse-tunnel stop${NC}"
echo -e "Перезапуск:      ${GREEN}/etc/init.d/reverse-tunnel restart${NC}"
echo -e "Статус:          ${GREEN}/etc/init.d/reverse-tunnel status${NC}"
echo -e "Включить автозапуск:   ${GREEN}/etc/init.d/reverse-tunnel enable${NC}"
echo -e "Отключить автозапуск:  ${GREEN}/etc/init.d/reverse-tunnel disable${NC}"

echo -e "\n${YELLOW}Просмотр логов:${NC}"
echo -e "logread | grep autossh"

echo -e "\n${YELLOW}Редактирование конфигурации через UCI:${NC}"
echo -e "Просмотр настроек:     ${GREEN}uci show reverse-tunnel${NC}"
echo -e "Изменение настроек:    ${GREEN}uci set reverse-tunnel.@general[0].vps_ip='новый_ip'${NC}"
echo -e "Применение изменений:  ${GREEN}uci commit reverse-tunnel${NC}"

echo -e "\n${YELLOW}Резервное копирование:${NC}"
if [ -f /etc/config/reverse-tunnel.backup ]; then
    echo -e "Резервная копия предыдущей конфигурации: ${GREEN}/etc/config/reverse-tunnel.backup${NC}"
fi

# Проверка существования директорий и файлов конфигурации
mkdir -p /etc/ssh
mkdir -p /etc/default

# Проверка и создание конфига для автоматического восстановления соединения
if [ ! -f /etc/ssh/ssh_config ] || ! grep -q "ServerAliveInterval" /etc/ssh/ssh_config; then
    cat > /etc/ssh/ssh_config << EOF
ServerAliveInterval 30
ServerAliveCountMax 3
EOF
fi

# Проверка и создание настроек autossh
if [ ! -f /etc/default/autossh ]; then
    cat > /etc/default/autossh << EOF
AUTOSSH_GATETIME=0
AUTOSSH_POLL=60
AUTOSSH_FIRST_POLL=30
AUTOSSH_PORT=0
AUTOSSH_DEBUG=1
EOF
fi

# Настройка файервола
echo -e "\n${GREEN}Проверка настроек файервола...${NC}"

# Проверяем, установлен ли файервол
if ! command -v fw3 &> /dev/null; then
    echo -e "${YELLOW}Файервол не установлен. Установка...${NC}"
    opkg update
    opkg install firewall
fi

# Функция для проверки, является ли IP адрес локальным
is_local_ip() {
    local ip=$1
    # Получаем IP адрес и маску LAN интерфейса
    local lan_ip=$(uci get network.lan.ipaddr)
    local lan_mask=$(uci get network.lan.netmask)
    
    # Если это localhost или IP совпадает с LAN IP
    if [ "$ip" = "localhost" ] || [ "$ip" = "$lan_ip" ]; then
        return 0
    fi
    
    # Проверяем, находится ли IP в диапазоне локальной сети
    local IFS=.
    local ip_a=($ip)
    local lan_a=($lan_ip)
    local mask_a=($lan_mask)
    
    for i in {0..3}; do
        if [ $((${ip_a[$i]} & ${mask_a[$i]})) -ne $((${lan_a[$i]} & ${mask_a[$i]})) ]; then
            return 1
        fi
    done
    return 0
}

# Создаем временный файл для новых правил
cat > /tmp/firewall.reverse-tunnel << EOF
# Reverse tunnel firewall rules
config rule
    option name 'Allow-SSH-In'
    option target 'ACCEPT'
    option src 'wan'
    option proto 'tcp'
    option dest_port '22'

EOF

# Добавляем правила для каждого туннеля
for ((i=0; i<${#tunnel_ports[@]}; i++)); do
    if is_local_ip "${local_hosts[i]}"; then
        cat >> /tmp/firewall.reverse-tunnel << EOF
config rule
    option name 'Allow-Tunnel-${tunnel_ports[i]}'
    option target 'ACCEPT'
    option src 'wan'
    option proto 'tcp'
    option dest_port '${local_ports[i]}'

EOF
    fi
done

# Проверяем существующие правила
NEED_RELOAD=0
if [ -f /etc/config/firewall ]; then
    for ((i=0; i<${#tunnel_ports[@]}; i++)); do
        if ! grep -q "Allow-Tunnel-${tunnel_ports[i]}" /etc/config/firewall; then
            NEED_RELOAD=1
            break
        fi
    done
else
    NEED_RELOAD=1
fi

# Если нужны новые правила, добавляем их
if [ $NEED_RELOAD -eq 1 ]; then
    echo -e "${YELLOW}Добавление новых правил файервола...${NC}"
    cat /tmp/firewall.reverse-tunnel >> /etc/config/firewall
    
    # Перезапускаем файервол
    echo -e "${GREEN}Перезапуск файервола...${NC}"
    /etc/init.d/firewall restart
else
    echo -e "${GREEN}Все необходимые правила файервола уже настроены${NC}"
fi

# Удаляем временный файл
rm /tmp/firewall.reverse-tunnel

# Добавляем информацию о файерволе в вывод
echo -e "\n${YELLOW}Настройки файервола:${NC}"
echo -e "Конфигурация файервола: ${GREEN}/etc/config/firewall${NC}"
echo -e "Управление файерволом:"
echo -e "Перезапуск:  ${GREEN}/etc/init.d/firewall restart${NC}"
echo -e "Статус:      ${GREEN}/etc/init.d/firewall status${NC}"
