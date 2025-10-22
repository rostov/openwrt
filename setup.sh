#!/bin/sh

# Скрипт начальной настройки OpenWRT
# Сохранить как /tmp/setup.sh, сделать исполняемым и запустить

# Список пакетов для установки (можно дополнять - каждый пакет на новой строке)
PACKAGES="
bash                    # Основная оболочка
bash-completion         # Автодополнение для bash
# coreutils-timeout     # Утилита timeout (пока не нужна)
curl                    # Загрузка файлов из интернета
file                    # Определение типа файлов
htop                    # Продвинутый монитор процессов
nano                    # Простой текстовый редактор
# rsync                   # Синхронизация файлов
# sudo                    # Выполнение команд от другого пользователя
# tmux                    # Менеджер терминалов
wget                    # Альтернатива curl для загрузки
"

# Дополнительные пакеты (опциональные)
OPTIONAL_PACKAGES="
# bind-tools              # DNS утилиты (dig, nslookup)
# git                   # Система контроля версий
iperf3                  # Тестирование скорости сети
# nmap                    # Сканер сети
python3                 # Интерпретатор Python 3
# python3-pip           # Менеджер пакетов Python
# tcpdump                 # Анализ сетевого трафика
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

# Обновление списка пакетов
log "Обновление списка пакетов..."
opkg update
check_success "Список пакетов обновлен" "Не удалось обновить список пакетов"

# Показываем основные пакеты
log "Основные пакеты:"
show_packages "$PACKAGES"

# Установка основных пакетов
log "Установка основных пакетов..."
for pkg in $(echo "$PACKAGES" | grep -v '^$' | grep -v '^#'); do
    # Берется только первое слово из строки, комментарии игнорируются
    pkg_clean=$(echo $pkg | awk '{print $1}')
    log "Устанавливаю $pkg_clean..."
    opkg install $pkg_clean
    if [ $? -ne 0 ]; then
        warn "Не удалось установить пакет $pkg_clean"
    fi
done

# Смена оболочки по умолчанию на bash
log "Настройка bash как оболочки по умолчанию..."
if [ -f /usr/bin/bash ]; then
    sed -i 's|/bin/ash|/usr/bin/bash|g' /etc/passwd
    check_success "Bash установлен как оболочка по умолчанию" "Не удалось изменить оболочку по умолчанию"
else
    error "Bash не установлен, пропускаем смену оболочки"
fi

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
    for pkg in $(echo "$OPTIONAL_PACKAGES" | grep -v '^$' | grep -v '^#'); do
        # Берется только первое слово из строки, комментарии игнорируются
        pkg_clean=$(echo $pkg | awk '{print $1}')
        log "Устанавливаю $pkg_clean..."
        opkg install $pkg_clean
        if [ $? -ne 0 ]; then
            warn "Не удалось установить пакет $pkg_clean"
        fi
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
