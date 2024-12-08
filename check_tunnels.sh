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

# Добавляем в cron
# */5 * * * * /root/check_tunnels.sh 