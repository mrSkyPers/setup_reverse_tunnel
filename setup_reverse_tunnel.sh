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