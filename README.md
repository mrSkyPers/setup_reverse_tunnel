# Настройка обратного SSH-туннеля для OpenWRT

Набор скриптов для автоматической настройки обратного SSH-туннеля между OpenWRT и VPS сервером.

## Описание

Эти скрипты автоматизируют процесс настройки безопасного обратного SSH-туннеля, который позволяет получить доступ к устройству OpenWRT через VPS сервер, даже если устройство находится за NAT.

### Возможности
- Поддержка OpenSSH и Dropbear
- Автоматическая настройка firewall на VPS
- Создание и настройка SSH-ключей
- Настройка автозапуска туннеля
- Мониторинг состояния туннеля

## Использование

### 1. Настройка VPS
Сначала настройте VPS сервер:
```bash
sh <(wget -O - https://raw.githubusercontent.com/vkust/setup_reverse_tunnel/main/setup_vps.sh)
```

Скрипт:
- Настроит SSH сервер
- Настроит firewall (UFW или IPTables)
- Создаст скрипт мониторинга туннелей
- Добавит мониторинг в cron

### 2. Настройка OpenWRT
После настройки VPS, запустите на устройстве OpenWRT:
```bash
sh <(wget -O - https://raw.githubusercontent.com/vkust/setup_reverse_tunnel/main/setup_reverse_tunnel.sh)
```

Скрипт:
- Установит и настроит SSH (OpenSSH или Dropbear)
- Создаст SSH-ключи
- Настроит обратный туннель
- Создаст сервис автозапуска

## Требования
- VPS с root доступом
- Устройство с OpenWRT
- Доступ к интернету на обоих устройствах

## После установки

1. Проверьте статус туннеля на OpenWRT:
```bash
/etc/init.d/reverse-tunnel status
```

2. Проверьте состояние туннелей на VPS:
```bash
/root/check_tunnels.sh
```

## Управление туннелем

На OpenWRT доступны команды:
```bash
/etc/init.d/reverse-tunnel start    # Запуск туннеля
/etc/init.d/reverse-tunnel stop     # Остановка туннеля
/etc/init.d/reverse-tunnel restart  # Перезапуск туннеля
/etc/init.d/reverse-tunnel enable   # Включить автозапуск
/etc/init.d/reverse-tunnel disable  # Отключить автозапуск
```