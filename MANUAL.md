# Руководство по ручной настройке обратного SSH-туннеля

В этом руководстве описан процесс ручной настройки обратного SSH-туннеля между устройством OpenWRT и VPS сервером.

## Содержание
- [Настройка VPS сервера](#настройка-vps-сервера)
  - [Настройка SSH](#1-настройка-ssh)
  - [Настройка Firewall](#2-настройка-firewall)
  - [Настройка параметров ядра](#3-настройка-параметров-ядра)
  - [Настройка Fail2Ban](#4-настройка-fail2ban)
- [Настройка OpenWRT](#настройка-openwrt)
  - [Установка SSH](#1-установка-ssh)
  - [Генерация SSH ключей](#2-генерация-ssh-ключей)
  - [Копирование ключа на VPS](#3-копирование-ключа-на-vps)
  - [Создание init.d скрипта](#4-создание-initd-скрипта)
  - [Настройка прав и запуск](#5-настройка-прав-и-запуск)
  - [Мониторинг туннеля](#6-мониторинг-туннеля-на-vps)
  - [Проверка работы](#7-проверка-работы)

## Настройка VPS сервера

### 1. Настройка SSH

1. Откройте конфигурационный файл:
```bash
nano /etc/ssh/sshd_config
```

2. Добавьте или измените следующие параметры:
```
AllowTcpForwarding yes
GatewayPorts yes
ClientAliveInterval 30
ClientAliveCountMax 3
```

3. Перезапустите SSH сервер:
```bash
systemctl restart sshd
```

### 2. Настройка Firewall

#### Вариант с UFW:
```bash
# Установка UFW
apt install ufw

# Настройка базовых правил
ufw default deny incoming
ufw default allow outgoing

# Открытие портов
ufw allow 22/tcp
ufw allow ПОРТ_ТУННЕЛЯ/tcp

# Включение UFW
ufw enable
```

#### Вариант с IPTables:
```bash
# Очистка правил
iptables -F
iptables -X

# Базовые правила
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Открытие портов
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport ПОРТ_ТУННЕЛЯ -j ACCEPT

# Политика по умолчанию
iptables -P INPUT DROP

# Сохранение правил
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
```

### 3. Настройка параметров ядра
```bash
# Редактируем sysctl.conf
nano /etc/sysctl.conf

# Добавляем параметры
net.ipv4.ip_forward=1
net.ipv4.tcp_max_syn_backlog=65535

# Применяем изменения
sysctl -p
```

### 4. Настройка Fail2Ban

1. Установка Fail2Ban:
```bash
apt update
apt install -y fail2ban
```

2. Создание конфигурации:
```bash
nano /etc/fail2ban/jail.local
```

3. Добавьте следующую конфигурацию:
```
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 300
bantime = 3600
```

4. Перезапустите службу:
```bash
systemctl restart fail2ban
```

5. Проверка статуса:
```bash
fail2ban-client status sshd
```

Полезные команды Fail2Ban:
```bash
# Просмотр логов
tail -f /var/log/fail2ban.log

# Список заблокированных IP
fail2ban-client get sshd banip

# Разблокировать IP
fail2ban-client set sshd unbanip IP_АДРЕС
```

## Настройка OpenWRT

### 1. Установка SSH

#### Для OpenSSH:
```bash
opkg update
opkg install openssh-server openssh-sftp-server openssh-keygen
/etc/init.d/sshd enable
/etc/init.d/sshd start
```

#### Для Dropbear:
```bash
opkg update
opkg install dropbear
/etc/init.d/dropbear enable
/etc/init.d/dropbear start
```

### 2. Генерация SSH ключей

#### Для OpenSSH:
```bash
mkdir -p /root/.ssh
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""
```

#### Для Dropbear:
```bash
mkdir -p /root/.ssh
dropbearkey -t rsa -f /root/.ssh/id_rsa
dropbearkey -y -f /root/.ssh/id_rsa | grep "^ssh-rsa" > /root/.ssh/id_rsa.pub
chmod 600 /root/.ssh/id_rsa
chmod 644 /root/.ssh/id_rsa.pub
```

### 3. Копирование ключа на VPS
```bash
# Для OpenSSH
cat /root/.ssh/id_rsa.pub | ssh -p ПОРТ user@VPS_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"

# Для Dropbear
cat /root/.ssh/id_rsa.pub | dbclient -p ПОРТ user@VPS_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
```

### 4. Создание init.d скрипта

1. Создайте файл конфигурации:
```bash
mkdir -p /etc/config
nano /etc/config/reverse-tunnel
```

2. Добавьте конфигурацию:
```
config reverse-tunnel 'general'
    option enabled '1'
    option ssh_port 'SSH_ПОРТ'
    option vps_user 'ИМЯ_ПОЛЬЗОВАТЕЛЯ'
    option vps_ip 'IP_АДРЕС_VPS'

config tunnel
    option remote_port 'УДАЛЕННЫЙ_ПОРТ'
    option local_port 'ЛОКАЛЬНЫЙ_ПОРТ'
    option local_host 'localhost'
```

3. Создайте init.d скрипт:
```bash
nano /etc/init.d/reverse-tunnel
```

4. Добавьте содержимое:
```bash
#!/bin/sh /etc/rc.common

START=99
STOP=15
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command ssh -NT -i /root/.ssh/id_rsa \
        -R ПОРТ_ТУННЕЛЯ:localhost:ЛОКАЛЬНЫЙ_ПОРТ \
        user@VPS_IP -p SSH_ПОРТ
    
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
```

### 5. Настройка прав и запуск
```bash
chmod +x /etc/init.d/reverse-tunnel
/etc/init.d/reverse-tunnel enable
/etc/init.d/reverse-tunnel start
```

### 6. Мониторинг туннеля на VPS

1. Создайте скрипт мониторинга:
```bash
nano /root/check_tunnels.sh
```

2. Добавьте содержимое:
```bash
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
```

3. Настройте права и добавьте в cron:
```bash
chmod +x /root/check_tunnels.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /root/check_tunnels.sh") | crontab -
```

### 7. Проверка работы
```bash
# На OpenWRT
/etc/init.d/reverse-tunnel status

# На VPS
netstat -tlpn | grep ssh
/root/check_tunnels.sh
```

## Дополнительные рекомендации

### Безопасность
1. Используйте нестандартный порт для SSH
2. Настройте fail2ban для защиты от брутфорса
3. Регулярно обновляйте систему
4. Используйте сложные пароли
5. Ограничьте доступ по IP если возможно

### Мониторинг
1. Регулярно проверяйте логи
2. Настройте оповещения при падении туннеля
3. Следите за нагрузкой на систему

### Обслуживание
1. Делайте резервные копии конфигурации
2. Документируйте все изменения
3. Проверяйте работу туннеля после обновлений системы

## Устранение неполадок

### Проблемы с подключением
1. Проверьте статус SSH сервера:
```bash
systemctl status sshd
```

2. Проверьте открытые порты:
```bash
netstat -tlpn | grep ssh
```

3. Проверьте правила firewall:
```bash
# Для UFW
ufw status numbered

# Для IPTables
iptables -L INPUT -n --line-numbers
```

4. Проверьте логи:
```bash
tail -f /var/log/auth.log
tail -f /var/log/fail2ban.log
```

### Проблемы с производительностью
1. Мониторинг системы:
```bash
top
htop
```

2. Проверка сети:
```bash
iftop
nethogs
```

3. Проверка туннелей:
```bash
/root/check_tunnels.sh
```

## Заключение

Это полное руководство по настройке обратного SSH-туннеля. Рекомендуется адаптировать конфигурацию под конкретные требования и регулярно проверять работоспособность системы.

## Полезные команды

### Управление туннелем на OpenWRT
```bash
/etc/init.d/reverse-tunnel start    # Запуск туннеля
/etc/init.d/reverse-tunnel stop     # Остановка туннеля
/etc/init.d/reverse-tunnel restart  # Перезапуск туннеля
/etc/init.d/reverse-tunnel enable   # Включить автозапуск
/etc/init.d/reverse-tunnel disable  # Отключить автозапуск
```

### Управление Fail2Ban на VPS
```bash
fail2ban-client status              # Общий статус
fail2ban-client status sshd         # Статус SSH jail
fail2ban-client set sshd unbanip IP # Разблокировать IP
```

### Мониторинг на VPS
```bash
/root/check_tunnels.sh             # Проверка туннелей
tail -f /var/log/auth.log          # Мониторинг логов SSH
tail -f /var/log/fail2ban.log      # Мониторинг логов Fail2Ban
``` 