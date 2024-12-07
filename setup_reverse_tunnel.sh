#!/bin/sh

# Установка цветов для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
            printf '\n\033[32mУстановка OpenSSH...\033[0m\n'
            opkg update
            opkg install openssh-server openssh-sftp-server
            /etc/init.d/sshd enable
            /etc/init.d/sshd start
        else
            printf '\n\033[32mOpenSSH уже установлен\033[0m\n'
        fi
        ;;
esac

# Установка sshpass для автоматического ввода пароля
if ! command -v sshpass &> /dev/null; then
    printf '\n\033[32mУстановка sshpass...\033[0m\n'
    opkg update
    opkg install sshpass
else
    printf '\n\033[32msshpass уже установлен\033[0m\n'
fi

# Запрос данных VPS
if [ -f /etc/config/reverse-tunnel ]; then
    printf '\n\033[33mОбнаружена существующая конфигурация туннеля.\033[0m\n'
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
        printf '\n\033[33mСоздание новой конфигурации...\033[0m\n'
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
    printf '\n\033[33mНастройка туннеля %d:\033[0m\n' "$i"
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
printf '\n\033[32mГенерация SSH-ключей...\033[0m\n'
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
printf '\n\033[32mКопирование публичного ключа на VPS...\033[0m\n'
# Создаем директорию .ssh если её нет
mkdir -p /root/.ssh

# Добавляем хост в known_hosts если его там нет
if ! grep -q "$vps_ip" /root/.ssh/known_hosts 2>/dev/null; then
    ssh-keyscan -p $ssh_port $vps_ip >> /root/.ssh/known_hosts 2>/dev/null
fi

if [ "$ssh_choice" = "2" ]; then
    # Для Dropbear используем cat и ssh для копирования ключа
    KEY=$(cat /root/.ssh/id_rsa.pub)
    sshpass -p "$vps_password" ssh -p $ssh_port "${vps_user}@${vps_ip}" "mkdir -p ~/.ssh && echo '$KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
else
    # Для OpenSSH используем ssh-copy-id
    sshpass -p "$vps_password" ssh-copy-id -p $ssh_port "${vps_user}@${vps_ip}"
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
    printf '\n\033[32mУстановка autossh...\033[0m\n'
    opkg update
    opkg install autossh
else
    printf '\n\033[32mautossh уже установлен\033[0m\n'
fi

printf '\n\033[32mНастройка завершена!\033[0m\n'
printf "Для подключения к OpenWRT используйте следующие команды на вашем VPS сервере:\n\n"

for remote_port in $tunnel_ports; do
    local_host=$(echo $local_hosts | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    local_port=$(echo $local_ports | cut -d' ' -f$(echo $tunnel_ports | tr ' ' '\n' | grep -n $remote_port | cut -d':' -f1))
    printf "Туннель %d: ssh -p %d root@localhost (-> %s:%d)\n" "$i" "$remote_port" "$local_host" "$local_port"
    i=$((i + 1))
done

printf '\n\033[33mСозданные файлы и конфигурации:\033[0m\n'
printf "\n1. Основные конфигурационные файлы:\n"
printf "   - Конфигурация туннелей: \033[32m/etc/config/reverse-tunnel\033[0m\n"
printf "   - Скрипт автозапуска: \033[32m/etc/init.d/reverse-tunnel\033[0m\n"

printf "\n2. SSH конфигурация:\n"
if [ "$ssh_choice" = "2" ]; then
    printf "   - Конфигурация Dropbear: \033[32m/etc/config/dropbear\033[0m\n"
else
    printf "   - Конфигурация OpenSSH: \033[32m/etc/config/sshd\033[0m\n"
fi
printf "   - SSH ключи: \033[32m/root/.ssh/id_rsa\033[0m (приватный) и \033[32m/root/.ssh/id_rsa.pub\033[0m (публичный)\n"
printf "   - Настройки SSH клиента: \033[32m/etc/ssh/ssh_config\033[0m\n"

printf "\n3. Настройки AutoSSH:\n"
printf "   - Конфигурация AutoSSH: \033[32m/etc/default/autossh\033[0m\n"

printf '\n\033[33mУправление службой:\033[0m\n'
printf "Запуск:          \033[32m/etc/init.d/reverse-tunnel start\033[0m\n"
printf "Остановка:       \033[32m/etc/init.d/reverse-tunnel stop\033[0m\n"
printf "Перезапуск:      \033[32m/etc/init.d/reverse-tunnel restart\033[0m\n"
printf "Статус:          \033[32m/etc/init.d/reverse-tunnel status\033[0m\n"
printf "Включить автозапуск:   \033[32m/etc/init.d/reverse-tunnel enable\033[0m\n"
printf "Отключить автозапуск:  \033[32m/etc/init.d/reverse-tunnel disable\033[0m\n"

printf '\n\033[33mПросмотр логов:\033[0m\n'
printf "logread | grep autossh\n"

printf '\n\033[33mРедактирование конфигурации через UCI:\033[0m\n'
printf "Просмотр настроек:     \033[32muci show reverse-tunnel\033[0m\n"
printf "Изменение настроек:    \033[32muci set reverse-tunnel.@general[0].vps_ip='новый_ip'\033[0m\n"
printf "Применение изменений:  \033[32muci commit reverse-tunnel\033[0m\n"

printf '\n\033[33mРезервное копирование:\033[0m\n'
if [ -f /etc/config/reverse-tunnel.backup ]; then
    printf "Резервная копия предыдущей конфигурации: \033[32m/etc/config/reverse-tunnel.backup\033[0m\n"
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
printf '\n\033[32mПроверка настроек файервола...\033[0m\n'

# Проверяем, установлен ли файервол
if ! command -v fw3 &> /dev/null; then
    printf '\033[33mФайервол не установлен. Установка...\033[0m\n'
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
    printf '\033[33mДобавление новых правил файервола...\033[0m\n'
    cat /tmp/firewall.reverse-tunnel >> /etc/config/firewall
    
    # Перезапускаем файервол
    printf '\033[32mПерезапуск файервола...\033[0m\n'
    /etc/init.d/firewall restart
else
    printf '\033[32mВсе необходимые правила файервола уже настроены\033[0m\n'
fi

# Удаляем временный файл
rm /tmp/firewall.reverse-tunnel

# Добавляем информацию о файерволе в вывод
printf '\n\033[33mНастройки файервола:\033[0m\n'
printf "Конфигурация файервола: \033[32m/etc/config/firewall\033[0m\n"
printf "Управление файерволом:\n"
printf "Перезапуск:  \033[32m/etc/init.d/firewall restart\033[0m\n"
printf "Статус:      \033[32m/etc/init.d/firewall status\033[0m\n"
