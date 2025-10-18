#!/bin/sh

# Скрипт установки и настройки hd-idle для OpenWRT
# Проверяет доступность пакета, предлагает альтернативы и настраивает автозагрузку

LOG_FILE="/tmp/hd-idle-install.log"
HD_IDLE_CONFIG="/etc/config/hd-idle"

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Функция проверки установки пакета
is_package_installed() {
    opkg list-installed | grep -q "^$1 "
}

# Функция проверки запуска службы
is_service_running() {
    /etc/init.d/"$1" enabled && /etc/init.d/"$1" running
}

# Функция остановки и отключения службы
disable_service() {
    local service=$1
    if is_service_running "$service"; then
        log "Останавливаем службу $service..."
        /etc/init.d/"$service" stop >> "$LOG_FILE" 2>&1
        /etc/init.d/"$service" disable >> "$LOG_FILE" 2>&1
        log "Служба $service отключена"
        return 0
    else
        log "Служба $service не запущена"
        return 1
    fi
}

# Функция установки hd-idle из исходников
install_from_source() {
    log "Попытка установки hd-idle из исходников..."
    
    # Устанавливаем необходимые пакеты для компиляции
    opkg update >> "$LOG_FILE" 2>&1
    opkg install gcc make >> "$LOG_FILE" 2>&1
    
    if [ $? -ne 0 ]; then
        log "Ошибка: не удалось установить компилятор и make"
        return 1
    fi
    
    # Создаем временную директорию для сборки
    BUILD_DIR="/tmp/hd-idle-build"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR" || return 1
    
    # Скачиваем исходники hd-idle
    wget -q https://sourceforge.net/projects/hd-idle/files/hd-idle-1.05.tgz >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "Ошибка: не удалось скачать исходники hd-idle"
        return 1
    fi
    
    # Распаковываем и компилируем
    tar -xzf hd-idle-1.05.tgz >> "$LOG_FILE" 2>&1
    cd hd-idle || return 1
    make >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        # Копируем бинарник и создаем init скрипт
        cp hd-idle /usr/sbin/
        chmod +x /usr/sbin/hd-idle
        create_init_script
        log "hd-idle успешно установлен из исходников"
        return 0
    else
        log "Ошибка компиляции hd-idle из исходников"
        return 1
    fi
}

# Функция создания init скрипта для hd-idle
create_init_script() {
    cat > /etc/init.d/hd-idle << 'EOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/hd-idle -i 600
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
    chmod +x /etc/init.d/hd-idle
}

# Функция настройки hdparm
setup_hdparm() {
    log "Настройка hdparm для управления временем отключения диска..."
    
    # Ищем подключенные диски
    DISKS=$(lsblk -nd -o NAME | grep -E '^sd[a-z]$')
    
    if [ -z "$DISKS" ]; then
        log "Не найдено подключенных дисков"
        return 1
    fi
    
    for disk in $DISKS; do
        log "Настройка hdparm для диска /dev/$disk"
        # Устанавливаем время простоя 10 минут (значение 120)
        hdparm -S 120 "/dev/$disk" >> "$LOG_FILE" 2>&1
        
        # Добавляем в автозагрузку
        if ! grep -q "hdparm -S 120 /dev/$disk" /etc/rc.local 2>/dev/null; then
            echo "hdparm -S 120 /dev/$disk &" >> /etc/rc.local
        fi
    done
    
    chmod +x /etc/rc.local
    log "hdparm настроен для автоматического отключения дисков через 10 минут простоя"
}

# Основная логика скрипта
main() {
    log "Начало установки hd-idle"
    
    # Проверяем доступность пакета в репозитории
    log "Проверка доступности пакета hd-idle в репозитории..."
    opkg update >> "$LOG_FILE" 2>&1
    
    if opkg list | grep -q "^hd-idle "; then
        log "Пакет hd-idle найден в репозитории, устанавливаем..."
        opkg install hd-idle >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            log "hd-idle успешно установлен из репозитория"
        else
            log "Ошибка установки hd-idle из репозитория"
        fi
    else
        log "Пакет hd-idle не найден в репозитории"
        echo ""
        echo "Пакет hd-idle не найден в репозитории OpenWRT."
        echo "Выберите вариант:"
        echo "1. Попытаться установить из исходников"
        echo "2. Использовать hdparm для управления диском"
        echo "3. Выйти"
        echo ""
        
        while true; do
            printf "Ваш выбор [1-3]: "
            read -r choice
            case $choice in
                1)
                    if install_from_source; then
                        break
                    else
                        echo "Не удалось установить из исходников. Попробуйте другой вариант."
                    fi
                    ;;
                2)
                    setup_hdparm
                    log "Настроен hdparm. Скрипт завершает работу."
                    exit 0
                    ;;
                3)
                    log "Установка отменена пользователем"
                    exit 0
                    ;;
                *)
                    echo "Неверный выбор. Введите 1, 2 или 3."
                    ;;
            esac
        done
    fi
    
    # Проверяем, установился ли hd-idle
    if is_package_installed "hd-idle" || [ -x "/usr/sbin/hd-idle" ]; then
        log "hd-idle успешно установлен, запускаем службу..."
        
        # Включаем и запускаем hd-idle
        /etc/init.d/hd-idle enable >> "$LOG_FILE" 2>&1
        /etc/init.d/hd-idle start >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            log "Служба hd-idle успешно запущена"
            
            # Отключаем smartd если он запущен
            if disable_service "smartd"; then
                log "smartd был отключен, так как hd-idle успешно установлен и запущен"
                echo "smartd отключен, управление диском передано hd-idle"
            fi
            
            # Настраиваем hd-idle (базовые настройки)
            if [ -f "$HD_IDLE_CONFIG" ]; then
                uci set hd-idle.@hd-idle[0].idle_time_interval='600'
                uci set hd-idle.@hd-idle[0].enabled='1'
                uci commit hd-idle
                log "Конфигурация hd-idle обновлена"
            fi
            
            echo "Установка и настройка hd-idle завершена успешно!"
            echo "Диск будет отключаться после 10 минут простоя"
            
        else
            log "Ошибка запуска службы hd-idle"
            echo "Внимание: hd-idle установлен, но не удалось запустить службу"
        fi
    else
        log "hd-idle не установлен, несмотря на попытки установки"
        echo "Ошибка: hd-idle не удалось установить"
    fi
    
    log "Завершение работы скрипта установки"
}

# Запуск основной функции
main
