#!/bin/sh

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция для цветного вывода
print_msg() {
    local color="$1"
    local msg="$2"
    printf "${color}${msg}${NC}\n"
}

# Функция проверки IP адреса
validate_ip() {
    local ip="$1"
    if echo "$ip" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null; then
        for octet in $(echo "$ip" | tr '.' ' '); do
            if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Функция проверки порта
validate_port() {
    local port="$1"
    if echo "$port" | grep -E '^[0-9]+$' >/dev/null && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

# Функция настройки SSH
setup_ssh() {
    local ssh_type="$1"
    
    if [ "$ssh_type" = "dropbear" ]; then
        if ! command -v dropbear >/dev/null 2>&1; then
            print_msg "$BLUE" "Ус��ановка Dropbear..."
            opkg update
            opkg install dropbear
            /etc/init.d/dropbear enable
            /etc/init.d/dropbear start
        fi
        SSH_CMD="dbclient"
    else
        if ! command -v ssh >/dev/null 2>&1; then
            print_msg "$BLUE" "Установка OpenSSH..."
            opkg update
            opkg install openssh-server openssh-sftp-server openssh-keygen
            /etc/init.d/sshd enable
            /etc/init.d/sshd start
        fi
        SSH_CMD="/usr/bin/ssh"
    fi
}

# Функция генерации SSH ключей
generate_ssh_keys() {
    local ssh_type="$1"
    
    if [ ! -f /root/.ssh/id_rsa ]; then
        mkdir -p /root/.ssh
        if [ "$ssh_type" = "dropbear" ]; then
            dropbearkey -t rsa -f /root/.ssh/id_rsa
            dropbearkey -y -f /root/.ssh/id_rsa | grep "^ssh-rsa" > /root/.ssh/id_rsa.pub
        else
            ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
        fi
    fi
}

# Функция настройки SSH конфигурации
setup_ssh_config() {
    local ssh_type="$1"
    
    mkdir -p /etc/ssh
    
    # Общие настройки SSH клиента
    cat > /etc/ssh/ssh_config << EOF
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    StrictHostKeyChecking no
EOF

    # Настройки для OpenSSH сервера
    if [ "$ssh_type" != "dropbear" ]; then
        cat > /etc/ssh/sshd_config << EOF
AllowTcpForwarding yes
GatewayPorts yes
ClientAliveInterval 30
ClientAliveCountMax 3
EOF
    fi
}

# Основная функция
main() {
    print_msg "$BLUE" "Настройка обратного SSH-туннеля для OpenWRT\n"

    # Выбор SSH сервера
    print_msg "$YELLOW" "Выберите SSH сервер:"
    echo "1) OpenSSH (рекомендуется)"
    echo "2) Dropbear (установлен по умолчанию, меньше нагрузки на сервер)"
    read -p "Введите номер (1/2): " ssh_choice

    case "$ssh_choice" in
        2) ssh_type="dropbear" ;;
        *) ssh_type="openssh" ;;
    esac

    setup_ssh "$ssh_type"

    # Запрос параметров подключения
    while true; do
        read -p "Введите IP-адрес VPS сервера: " vps_ip
        if validate_ip "$vps_ip"; then
            break
        else
            print_msg "$RED" "Ошибка: некорректный формат IP-адреса"
        fi
    done

    read -p "Введите порт для SSH на VPS (по умолчанию 22): " ssh_port
    ssh_port=${ssh_port:-22}
    if ! validate_port "$ssh_port"; then
        print_msg "$RED" "Ошибка: некорректный порт"
        exit 1
    fi

    read -p "Введите имя пользователя на VPS: " vps_user

    # Настройка туннелей
    read -p "Сколько туннелей вы хотите настроить? " tunnel_count
    tunnel_ports=""
    local_ports=""
    local_hosts=""

    i=1
    while [ $i -le $tunnel_count ]; do
        print_msg "$YELLOW" "\nНастройка туннеля $i:"
        
        while true; do
            read -p "Введите удаленный порт для туннеля $i: " remote_port
            if validate_port "$remote_port"; then
                break
            else
                print_msg "$RED" "Ошибка: некорректный порт"
            fi
        done

        while true; do
            read -p "Введите локальный порт для туннеля $i: " local_port
            if validate_port "$local_port"; then
                break
            else
                print_msg "$RED" "Ошибка: некорректный порт"
            fi
        done

        read -p "Введите IP-адрес локального устройства (Enter для localhost): " local_host
        local_host=${local_host:-localhost}

        tunnel_ports="$tunnel_ports $remote_port"
        local_ports="$local_ports $local_port"
        local_hosts="$local_hosts $local_host"
        i=$((i + 1))
    done

    # Генерация и установка SSH ключей
    generate_ssh_keys "$ssh_type"
    setup_ssh_config "$ssh_type"

    # Продолжение в следующем сообщении...
}

main "$@"