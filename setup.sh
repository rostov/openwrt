#!/bin/sh

# Скрипт начальной настройки OpenWRT
# Сохранить как /tmp/setup.sh, сделать исполняемым и запустить

# ========== НАСТРОЙКИ СЕТЕЙ WiFi ==========
SSID_2GHZ="RouteRich_22"
SSID_5GHZ="RouteRich_55"
# Пароль будет запрошен во время выполнения скрипта

# Список пакетов для установки (можно дополнять - каждый пакет на новой строке)
PACKAGES="
# Основная оболочка вместо ash
bash
# Автодополнение для bash
bash-completion-bash
# Загрузка файлов из интернета
curl
# Определение типа файлов
file
# Продвинутый монитор процессов
htop
# Простой текстовый редактор
nano-full
# Альтернатива curl для загрузки
wget
"

# Дополнительные пакеты (опциональные)
OPTIONAL_PACKAGES="
# DNS утилиты (dig, nslookup)
#bind-tools
# Система контроля версий
#git
# Тестирование скорости сети
iperf3
# Сканер сети
#nmap
# Интерпретатор Python 3
#python3
# Менеджер пакетов Python
#python3-pip
# Анализ сетевого трафика
#tcpdump
"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Функция для проверки успешности выполнения команды
check_success() {
    if [ $? -eq 0 ]; then
        log "$1"
    else
        error "$2"
        exit 1
    fi
}

# Функция для вывода списка пакетов в алфавитном порядке
show_packages() {
    echo "Список пакетов для установки:"
    echo "=============================="
    echo "$1" | grep -v '^$' | sort | awk '{print "  • " $1}'
    echo "=============================="
}

# Функция для вывода списка пакетов в алфавитном порядке
show_packages() {
    echo "Список пакетов для установки:"
    echo "=============================="
    # Выводим только некомментированные строки, которые не пустые
    echo "$1" | grep -v '^#' | grep -v '^$' | sort | awk '{print "  • " $1}'
    echo "=============================="
}

# Функция для получения чистого списка пакетов (без комментариев и пустых строк)
get_clean_packages() {
    echo "$1" | grep -v '^#' | grep -v '^$'
}

# Функция для настройки WiFi
setup_wifi() {
    log "Настройка WiFi сетей..."
    
    # Запрашиваем пароль
    echo ""
    echo "=== НАСТРОЙКА WIFI СЕТЕЙ ==="
    read -s -p "Введите пароль для WiFi сетей $SSID_2GHZ и $SSID_5GHZ: " WIFI_PASSWORD
    echo
    read -s -p "Повторите пароль: " WIFI_PASSWORD_CONFIRM
    echo
    
    if [ "$WIFI_PASSWORD" != "$WIFI_PASSWORD_CONFIRM" ]; then
        error "Пароли не совпадают! Настройка WiFi пропущена."
        return 1
    fi
    
    if [ -z "$WIFI_PASSWORD" ] || [ ${#WIFI_PASSWORD} -lt 8 ]; then
        error "Пароль должен быть не менее 8 символов! Настройка WiFi пропущена."
        return 1
    fi
    
    log "Настраиваю WiFi сети..."
    
    # Создаем резервную копию конфигурации
    cp /etc/config/wireless /etc/config/wireless.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null
    
    # Генерируем хэш пароля
    local key=$(echo -n "$WIFI_PASSWORD" | openssl sha256 -hmac "salt" | cut -d' ' -f2 | cut -c1-32)
    
    # Настройка 2.4 GHz
    uci set wireless.@wifi-device[0].disabled='0'
    uci set wireless.@wifi-device[0].channel='auto'
    uci set wireless.@wifi-device[0].htmode='HT40'
    uci set wireless.@wifi-device[0].country='RU'
    uci set wireless.@wifi-device[0].txpower='20'
    
    uci set wireless.@wifi-iface[0].ssid="$SSID_2GHZ"
    uci set wireless.@wifi-iface[0].key="$WIFI_PASSWORD"
    uci set wireless.@wifi-iface[0].encryption='psk2'
    uci set wireless.@wifi-iface[0].isolate='0'
    
    # Настройка 5 GHz (если есть второй радио)
    if [ -n "$(uci get wireless.@wifi-device[1] 2>/dev/null)" ]; then
        uci set wireless.@wifi-device[1].disabled='0'
        uci set wireless.@wifi-device[1].channel='auto'
        uci set wireless.@wifi-device[1].htmode='HE160'
        uci set wireless.@wifi-device[1].country='RU'
        uci set wireless.@wifi-device[1].txpower='23'
        
        uci set wireless.@wifi-iface[1].ssid="$SSID_5GHZ"
        uci set wireless.@wifi-iface[1].key="$WIFI_PASSWORD"
        uci set wireless.@wifi-iface[1].encryption='psk2'
        uci set wireless.@wifi-iface[1].isolate='0'
    else
        warn "Второе радио (5 GHz) не найдено, настраиваю только 2.4 GHz"
    fi
    
    # Применяем изменения
    uci commit wireless
    if [ $? -eq 0 ]; then
        log "Конфигурация WiFi применена успешно"
        
        # Перезапускаем WiFi
        wifi reload
        sleep 3
        
        log "WiFi сети настроены:"
        log "  2.4 GHz: $SSID_2GHZ"
        if [ -n "$(uci get wireless.@wifi-device[1] 2>/dev/null)" ]; then
            log "  5 GHz: $SSID_5GHZ"
        fi
    else
        error "Ошибка применения конфигурации WiFi"
        return 1
    fi
    
    # Очищаем переменные с паролями
    unset WIFI_PASSWORD
    unset WIFI_PASSWORD_CONFIRM
}

# Обновление списка пакетов
log "Обновление списка пакетов..."
opkg update
check_success "Список пакетов обновлен" "Не удалось обновить список пакетов"

# Показываем основные пакеты
log "Основные пакеты:"
show_packages "$PACKAGES"

# Установка основных пакетов
log "Установка основных пакетов..."
for pkg in $(get_clean_packages "$PACKAGES"); do
    log "Устанавливаю $pkg..."
    opkg install $pkg
    if [ $? -ne 0 ]; then
        warn "Не удалось установить пакет $pkg"
    fi
done

# Смена оболочки по умолчанию на bash
log "Настройка bash как оболочки по умолчанию..."
if [ -f /bin/bash ]; then
    sed -i 's|/bin/ash|/bin/bash|g' /etc/passwd
    check_success "Bash установлен как оболочка по умолчанию" "Не удалось изменить оболочку по умолчанию"
else
    error "Bash не установлен, пропускаем смену оболочки"
fi

# Настройка WiFi сетей
setup_wifi

# Создание .bashrc для root со всеми настройками
log "Создание .bashrc для root..."
cat > /root/.bashrc << 'EOF'
# ~/.bashrc для root

# Если оболочка интерактивная
if [ -n "$PS1" ]; then
    # Настройки истории bash
    export HISTSIZE=1000
    export HISTFILESIZE=2000
    export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S - "
    export HISTCONTROL=ignoredups:erasedups
    export HISTIGNORE="ls:ll:cd:pwd:exit:history"

    # Сохранять историю после каждой команды
    PROMPT_COMMAND='history -a'

    # Цветной prompt с датой/временем
    export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\n\[\033[01;35m\][\D{%Y-%m-%d %H:%M:%S}]\[\033[00m\] \$ '

    # Алиасы
    alias ll='ls -la'
    alias lh='ls -lah'
    alias ..='cd ..'
    alias ...='cd ../..'
    alias grep='grep --color=auto'
    alias egrep='egrep --color=auto'
    alias fgrep='fgrep --color=auto'
    
    # Алиасы для OpenWRT
    alias opkg-update='opkg update'
    alias opkg-upgrade='opkg list-upgradable | cut -f 1 -d " " | xargs opkg upgrade'
    alias services='/etc/init.d/'
    alias log-system='logread'
    alias log-dmesg='dmesg'
    alias restart-network='/etc/init.d/network restart'
    alias status-all='/etc/init.d/* status'

    # Информация о системе при входе
    echo "=========================================="
    echo "$(cat /etc/banner)"
    #echo "Система: $(cat /etc/openwrt_release 2>/dev/null | grep _ID | cut -d'"' -f2 2>/dev/null || echo 'OpenWRT')"
    #echo "Версия: $(cat /etc/openwrt_release 2>/dev/null | grep _RELEASE | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    echo "Время работы: $(uptime)"
    echo "Память: $(free -m 2>/dev/null | awk 'NR==2{printf "Используется: %s/%sMB (%.2f%%)", $3,$2,$3*100/$2}' || echo 'N/A')"
    echo "=========================================="
fi
EOF

check_success ".bashrc создан" "Не удалось создать .bashrc"

# Настройка прав для истории
log "Настройка прав доступа для истории..."
touch /root/.bash_history
chmod 600 /root/.bash_history

# Предлагаем установить дополнительные пакеты
log "Дополнительные пакеты (опционально):"
show_packages "$OPTIONAL_PACKAGES"

read -p "Установить дополнительные пакеты? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Установка дополнительных пакетов..."
    for pkg in $(get_clean_packages "$OPTIONAL_PACKAGES"); do
        log "Устанавливаю $pkg..."
        opkg install $pkg 2>/dev/null || warn "Не удалось установить $pkg"
    done
fi

# Финальные настройки
log "Применение настроек..."
# Применяем настройки для текущей сессии
[ -f /root/.bashrc ] && . /root/.bashrc

log "Настройка завершена!"
echo ""
echo "Что было сделано:"
echo "✓ Установлены основные пакеты"
echo "✓ Настроен bash как оболочка по умолчанию"
echo "✓ Настроены WiFi сети:"
echo "  - 2.4 GHz: $SSID_2GHZ"
if [ -n "$(uci get wireless.@wifi-device[1] 2>/dev/null)" ]; then
    echo "  - 5 GHz: $SSID_5GHZ"
fi
echo "✓ Настроена история команд с временными метками"
echo "✓ Созданы полезные алиасы и функции"
echo "✓ Настроен цветной prompt"
echo ""
echo "Для применения всех изменений выполните:"
echo "  source ~/.bashrc"
echo "или перезайдите в систему"
echo ""
echo "Полезные команды:"
echo "  hists <текст>    - поиск в истории"
echo "  histclear        - очистка истории"
echo "  history          - просмотр истории с датами"
echo ""
echo "Чтобы добавить свои пакеты, отредактируйте переменные PACKAGES и OPTIONAL_PACKAGES в скрипте"
