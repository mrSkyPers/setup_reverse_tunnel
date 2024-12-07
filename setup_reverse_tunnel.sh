#!/bin/sh

# Установка цветов для вывода
esc=""
c_reset="${esc}[0m"
c_green="${esc}[32m"
c_blue="${esc}[34m"
c_yellow="${esc}[33m"

printf '\033[34mНастройка обратного SSH-туннеля для OpenWRT\033[0m\n\n'

# Выбор SSH сервера
printf '\033[33mВыберите SSH сервер:\033[0m\n'
echo "1) OpenSSH (рекомендуется)"
echo "2) Dropbear (установлен по умолчанию, меньше нагрузки на сервер)"
read -p "Введите номер (1/2): " ssh_choice

case $ssh_choice in
    2)
        if ! command -v dropbear > /dev/null 2>&1; then
            printf '\n\033[32mУстановка Dropbear...\033[0m\n'
            opkg update
            opkg install dropbear
            /etc/init.d/dropbear enable
            /etc/init.d/dropbear start
        else
            printf '\n\033[32mDropbear уже установлен\033[0m\n'
        fi
        ;;
    *)
        if ! command -v ssh > /dev/null 2>&1; then
            printf "\n%sУстановка OpenSSH...%s\n" "$c_green" "$c_reset"
            opkg update
            opkg install openssh-server openssh-sftp-server
            /etc/init.d/sshd enable
            /etc/init.d/sshd start
        else
            printf "\n%sOpenSSH уже установлен%s\n" "$c_green" "$c_reset"
        fi
        ;;
esac

# Установка sshpass для автоматического ввода пароля
if ! command -v sshpass &> /dev/null; then
    printf "\n%sУстановка sshpass...%s\n" "$c_green" "$c_reset"
    opkg update
    opkg install sshpass
else
    printf "\n%ssshpass уже установлен%s\n" "$c_green" "$c_reset"
fi

# Запрос данных VPS
if [ -f /etc/config/reverse-tunnel ]; then
    printf "\n%sОбнаружена существующая конфигурация туннеля.%s\n" "$c_yellow" "$c_reset"
    read -p "Хотите использовать существующую конфигурацию? (y/N): " use_existing
    if [ "$use_existing" = "y" ] || [ "$use_existing" = "Y" ]; then
        vps_ip=$(uci get reverse-tunnel.@general[0].vps_ip)
        vps_user=$(uci get reverse-tunnel.@general[0].vps_user)
        ssh_port=$(uci get reverse-tunnel.@general[0].ssh_port)
        echo "Загружена конфигурация:"
        echo "VPS IP: ${vps_ip}"
        echo "Пользователь: ${vps_user}"
        echo "SSH порт: ${ssh_port}"
    else
        printf "\n%sСоздание новой конфигурации...%s\n" "$c_yellow" "$c_reset"
        mv /etc/config/reverse-tunnel /etc/config/reverse-tunnel.backup
        echo "Предыдущая конфигурация сохранена как /etc/config/reverse-tunnel.backup"
    fi
fi

if [ "$use_existing" != "y" ] && [ "$use_existing" != "Y" ]; then
    read -p "Введите IP-адрес VPS сервера: " vps_ip
    read -p "Введите имя пользователя на VPS: " vps_user
    read -p "Введите порт для SSH на VPS (по умолчанию 22): " ssh_port
    ssh_port=${ssh_port:-22}
    read -s -p "Введите пароль пользователя на VPS: " vps_password
    echo ""
fi

# Массив для хранения туннелей (в sh нет массивов, используем строки)
tunnel_ports=""
local_ports=""
local_hosts=""

# Запрос количества туннелей
read -p "Сколько туннелей вы хотите настроить? " tunnel_count

i=1
while [ $i -le $tunnel_count ]; do
    printf "\n%sНастройка туннеля %d:%s\n" "$c_yellow" "$i" "$c_reset"
    read -p "Введите удаленный порт для туннеля $i (например 19999): " remote_port
    read -p "Введите локальный порт для туннеля $i (например 22): " local_port
    read -p "Введите IP-адрес локального устройства (нажмите Enter для localhost): " local_host
    local_host=${local_host:-localhost}
    tunnel_ports="$tunnel_ports $remote_port"
    local_ports="$local_ports $local_port"
    local_hosts="$local_hosts $local_host"
    i=$((i + 1))
done

# Создание SSH-ключей
printf "\n%sГенерация SSH-ключей...%s\n" "$c_green" "$c_reset"
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
printf "\n%sКопирование публичного ключа на VPS...%s\n" "$c_green" "$c_reset"
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
for remote_port in $tunnel_ports; do
    local_host=$(echo $local_hosts | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    local_port=$(echo $local_ports | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    echo "        -R ${remote_port}:${local_host}:${local_port} \\" >> /etc/init.d/reverse-tunnel
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
for remote_port in $tunnel_ports; do
    local_host=$(echo $local_hosts | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    local_port=$(echo $local_ports | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    cat >> /etc/config/reverse-tunnel << EOF
config tunnel
    option remote_port '${remote_port}'
    option local_port '${local_port}'
    option local_host '${local_host}'
EOF
done

# Установка прав и включение автозапуска
chmod +x /etc/init.d/reverse-tunnel
/etc/init.d/reverse-tunnel enable
/etc/init.d/reverse-tunnel start

# Установка autossh если не установлен
if ! command -v autossh &> /dev/null; then
    printf "\n%sУстановка autossh...%s\n" "$c_green" "$c_reset"
    opkg update
    opkg install autossh
else
    printf "\n%sautossh уже установлен%s\n" "$c_green" "$c_reset"
fi

printf "\n%sНастройка завершена!%s\n" "$c_green" "$c_reset"
printf "Для подключения к OpenWRT используйте следующие команды на вашем VPS сервере:\n\n"

for remote_port in $tunnel_ports; do
    local_host=$(echo $local_hosts | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    local_port=$(echo $local_ports | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    printf "Туннель %d: ssh -p %d root@localhost (-> %s:%d)\n" "$i" "$remote_port" "$local_host" "$local_port"
    i=$((i + 1))
done

printf "\n%sСозданные файлы и конфигурации:%s\n" "$c_yellow" "$c_reset"
printf "\n1. Основные конфигурационные файлы:\n"
printf "   - Конфигурация туннелей: %s/etc/config/reverse-tunnel%s\n" "$c_green" "$c_reset"
printf "   - Скрипт автозапуска: %s/etc/init.d/reverse-tunnel%s\n" "$c_green" "$c_reset"

printf "\n2. SSH конфигурация:\n"
if [ "$ssh_choice" = "2" ]; then
    printf "   - Конфигурация Dropbear: %s/etc/config/dropbear%s\n" "$c_green" "$c_reset"
else
    printf "   - Конфигурация OpenSSH: %s/etc/config/sshd%s\n" "$c_green" "$c_reset"
fi
printf "   - SSH ключи: %s/root/.ssh/id_rsa%s (приватный) и %s/root/.ssh/id_rsa.pub%s (публичный)\n" "$c_green" "$c_reset" "$c_green" "$c_reset"
printf "   - Настройки SSH клиента: %s/etc/ssh/ssh_config%s\n" "$c_green" "$c_reset"

printf "\n3. Настройки AutoSSH:\n"
printf "   - Конфигурация AutoSSH: %s/etc/default/autossh%s\n" "$c_green" "$c_reset"

printf "\n%sУправление службой:%s\n" "$c_yellow" "$c_reset"
printf "Запуск:          %s/etc/init.d/reverse-tunnel start%s\n" "$c_green" "$c_reset"
printf "Остановка:       %s/etc/init.d/reverse-tunnel stop%s\n" "$c_green" "$c_reset"
printf "Перезапуск:      %s/etc/init.d/reverse-tunnel restart%s\n" "$c_green" "$c_reset"
printf "Статус:          %s/etc/init.d/reverse-tunnel status%s\n" "$c_green" "$c_reset"
printf "Включить автозапуск:   %s/etc/init.d/reverse-tunnel enable%s\n" "$c_green" "$c_reset"
printf "Отключить автозапуск:  %s/etc/init.d/reverse-tunnel disable%s\n" "$c_green" "$c_reset"

printf "\n%sПросмотр логов:%s\n" "$c_yellow" "$c_reset"
printf "logread | grep autossh\n"

printf "\n%sРедактирование конфигурации через UCI:%s\n" "$c_yellow" "$c_reset"
printf "Просмотр настроек:     %suci show reverse-tunnel%s\n" "$c_green" "$c_reset"
printf "Изменение настроек:    %suci set reverse-tunnel.@general[0].vps_ip='новый_ip'%s\n" "$c_green" "$c_reset"
printf "Применение изменений:  %suci commit reverse-tunnel%s\n" "$c_green" "$c_reset"

printf "\n%sРезервное копирование:%s\n" "$c_yellow" "$c_reset"
if [ -f /etc/config/reverse-tunnel.backup ]; then
    printf "Резервная копия предыдущей конфигурации: %s/etc/config/reverse-tunnel.backup%s\n" "$c_green" "$c_reset"
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
printf "\n%sПроверка настроек файервола...%s\n" "$c_green" "$c_reset"

# Проверяем, установлен ли файервол
if ! command -v fw3 &> /dev/null; then
    printf "%sФайервол не установлен. Установка...%s\n" "$c_yellow" "$c_reset"
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
for remote_port in $tunnel_ports; do
    local_host=$(echo $local_hosts | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    local_port=$(echo $local_ports | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    if is_local_ip "$local_host"; then
        cat >> /tmp/firewall.reverse-tunnel << EOF
config rule
    option name 'Allow-Tunnel-${remote_port}'
    option target 'ACCEPT'
    option src 'wan'
    option proto 'tcp'
    option dest_port '${local_port}'

EOF
    fi
done

# Проверяем существующие правила
NEED_RELOAD=0
if [ -f /etc/config/firewall ]; then
    for remote_port in $tunnel_ports; do
        if ! grep -q "Allow-Tunnel-${remote_port}" /etc/config/firewall; then
            NEED_RELOAD=1
            break
        fi
    done
else
    NEED_RELOAD=1
fi

# Если нужны новые правила, добавляем их
if [ $NEED_RELOAD -eq 1 ]; then
    printf "%sДобавление новых правил файервола...%s\n" "$c_yellow" "$c_reset"
    cat /tmp/firewall.reverse-tunnel >> /etc/config/firewall
    
    # Перезапускаем файервол
    printf "%sПерезапуск файервола...%s\n" "$c_green" "$c_reset"
    /etc/init.d/firewall restart
else
    printf "%sВсе необходимые правила файервола уже настроены%s\n" "$c_green" "$c_reset"
fi

# Удаляем временный файл
rm /tmp/firewall.reverse-tunnel

# Добавляем информацию о файерволе в вывод
printf "\n%sНастройки файервола:%s\n" "$c_yellow" "$c_reset"
printf "Конфигурация файервола: %s/etc/config/firewall%s\n" "$c_green" "$c_reset"
printf "Управление файерволом:\n"
printf "Перезапуск:  %s/etc/init.d/firewall restart%s\n" "$c_green" "$c_reset"
printf "Статус:      %s/etc/init.d/firewall status%s\n" "$c_green" "$c_reset"
