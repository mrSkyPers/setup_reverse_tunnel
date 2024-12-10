#!/bin/sh

# Функция для запроса ввода портов
get_ports() {
    echo "Введите порты для проверки, разделенные пробелом (например, 22 80 443):"
    read -r PORTS
}

# Проверка наличия аргументов
if [ "$#" -eq 0 ]; then
    echo "Аргументы не переданы. Переходим к интерактивному вводу."
    get_ports
else
    PORTS="$@"
fi

# Проверка активных туннелей
if [ -z "$PORTS" ]; then
    echo "Нет активных туннелей для проверки."
    exit 0
fi

echo "Проверяем порты: $PORTS"

for port in $PORTS; do
    echo "Проверка порта: $port"
    if ! netstat -an | grep "LISTEN" | grep ":$port " > /dev/null; then
        echo "Туннель на порту $port не активен"
        logger "Reverse tunnel on port $port is down"
    else
        echo "Туннель на порту $port активен"
    fi
done

# Добавляем в cron
# */5 * * * * /root/check_tunnels.sh порт1 порт2 порт3 ... 