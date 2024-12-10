#!/bin/sh

# Функция для запроса ввода портов
get_ports() {
    echo "Введите порты для проверки, разделенные пробелом (например, 22 80 443):"
    read -r PORTS
}

# Запрос портов у пользователя
get_ports

# Проверка активных туннелей
if [ -z "$PORTS" ]; then
    echo "Нет активных туннелей для проверки."
    exit 0
fi

for port in $PORTS; do
    if ! netstat -an | grep "LISTEN" | grep ":$port " > /dev/null; then
        echo "Туннель на порту $port не активен"
        logger "Reverse tunnel on port $port is down"
    else
        echo "Туннель на порту $port активен"
    fi
done

# Добавляем в cron
# */5 * * * * /root/check_tunnels.sh 