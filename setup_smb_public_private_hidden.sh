#!/bin/sh
#
# === RouteRich Samba Setup Script ===
# Автоматическая настройка SMB-шары на OpenWRT.
# Создаёт публичную и приватную папку, добавляет пользователей и автозапуск.
#

### === 1. Настройки ===
MOUNT_POINT="/mnt/wd"            # Точка монтирования (можно изменить)
PUB_NAME="rr"                    # Имя публичной шары
PUB_USER="rr"                    # Пользователь публичной шары
PUB_PASS="123"                   # Пароль публичной шары
PRIV_NAME="private"              # Имя приватной шары
PRIV_USER="private_share_user"   # Пользователь приватной шары
SPINDOWN_MIN=10                  # Минуты простоя перед отключением питания диска

echo "=== Настройка SMB-шары на OpenWRT ==="

### === 2. Проверка и установка block-mount (для blkid/block info) ===
if ! command -v block >/dev/null 2>&1; then
    echo "[*] Устанавливаем пакет block-mount (для block info)..."
    opkg update && opkg install block-mount
else
    echo "[✓] Утилита block уже установлена"
fi

### === 3. Определяем первый подключённый диск (/dev/sda, /dev/sdb, ...) ===
DEV=$(for d in /dev/sd?; do [ -b "$d" ] && echo "$d" && break; done)
if [ -z "$DEV" ]; then
    echo "[x] Не найден подключённый диск!"
    exit 1
fi
echo "[✓] Найден диск: $DEV"

# --- Определяем, раздел это или весь диск ---
if [ -b "${DEV}1" ]; then
    DEV="${DEV}1"
    echo "[i] Использую раздел: $DEV"
fi

### === 4. Проверяем, не смонтирован ли диск уже ===
EXIST_MNT=$(mount | grep -m1 "$DEV" | awk '{print $3}')
if [ -n "$EXIST_MNT" ] && [ "$EXIST_MNT" != "$MOUNT_POINT" ]; then
    echo "[!] Диск уже смонтирован в $EXIST_MNT, размонтирую..."
    umount "$EXIST_MNT" || {
        echo "[x] Не удалось размонтировать $EXIST_MNT"
        exit 1
    }
    EXIST_MNT=""
fi

### === 5. Создание точки монтирования ===
if [ -z "$EXIST_MNT" ]; then
    mkdir -p "$MOUNT_POINT"
    mount "$DEV" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "[x] Не удалось смонтировать $DEV в $MOUNT_POINT"
        exit 1
    fi
fi
echo "[✓] Диск смонтирован в $MOUNT_POINT"

### === 6. Добавляем автоподключение в /etc/config/fstab ===
UUID=$(block info "$DEV" | grep -o 'UUID="[^"]*"' | cut -d'"' -f2)
uci delete fstab.@mount[0] 2>/dev/null
uci set fstab.@mount[-1]=mount
uci set fstab.@mount[-1].target="$MOUNT_POINT"
uci set fstab.@mount[-1].enabled='1'
uci set fstab.@mount[-1].fstype='ext4'
if [ -n "$UUID" ]; then
    uci set fstab.@mount[-1].uuid="$UUID"
else
    uci set fstab.@mount[-1].device="$DEV"
fi
uci commit fstab
echo "[✓] Добавлена запись в fstab (UUID=${UUID:-N/A})"

### === 7. Создаём папки ===
mkdir -p "$MOUNT_POINT/public" "$MOUNT_POINT/private"
chmod 777 "$MOUNT_POINT/public"
chmod 700 "$MOUNT_POINT/private"
chown nobody:nogroup "$MOUNT_POINT/public"
chown root:root "$MOUNT_POINT/private"
echo "[✓] Папки public и private созданы"

### === 8. Настройка ksmbd ===
uci -q delete ksmbd
uci set ksmbd.globals=globals
uci set ksmbd.globals.workgroup='WORKGROUP'
uci set ksmbd.globals.description='RouteRich SMB Server'
uci set ksmbd.globals.interface='lan'
uci set ksmbd.globals.server_min_protocol='SMB2_10'
uci set ksmbd.globals.server_max_protocol='SMB3'

# --- Публичная шара ---
uci add ksmbd share >/dev/null
uci set ksmbd.@share[-1].name="$PUB_NAME"
uci set ksmbd.@share[-1].path="$MOUNT_POINT/public"
uci set ksmbd.@share[-1].read_only='no'
uci set ksmbd.@share[-1].guest_ok='yes'
uci set ksmbd.@share[-1].create_mask='0666'
uci set ksmbd.@share[-1].dir_mask='0777'
uci set ksmbd.@share[-1].browseable='yes'

# --- Приватная шара ---
uci add ksmbd share >/dev/null
uci set ksmbd.@share[-1].name="$PRIV_NAME"
uci set ksmbd.@share[-1].path="$MOUNT_POINT/private"
uci set ksmbd.@share[-1].read_only='no'
uci set ksmbd.@share[-1].guest_ok='no'
uci set ksmbd.@share[-1].browseable='no'
uci set ksmbd.@share[-1].create_mask='0660'
uci set ksmbd.@share[-1].dir_mask='0770'
uci set ksmbd.@share[-1].valid_users="$PRIV_USER"

uci commit ksmbd

### === 9. Добавляем пользователей ===
echo "[*] Добавляем пользователей Samba..."
ksmbd.adduser -d "$PUB_USER" >/dev/null 2>&1
ksmbd.adduser "$PUB_USER" <<EOF
$PUB_PASS
$PUB_PASS
EOF

# Пароль приватного пользователя запрашиваем
echo
read -p "Введите пароль для приватного пользователя ($PRIV_USER): " PRIV_PASS
ksmbd.adduser -d "$PRIV_USER" >/dev/null 2>&1
echo -e "$PRIV_PASS\n$PRIV_PASS" | ksmbd.adduser "$PRIV_USER"

### === 10. Перезапуск ksmbd ===
/etc/init.d/ksmbd restart
/etc/init.d/ksmbd enable

### === 11. Настройка автоотключения диска ===
SECS=$((SPINDOWN_MIN * 60 / 5))
if [ $SECS -gt 1 ] && [ $SECS -lt 241 ]; then
    echo "[*] Настраиваю автоотключение питания диска через $SPINDOWN_MIN мин..."
    hdparm -S $SECS "$DEV" >/dev/null 2>&1
else
    echo "[!] Время простоя $SPINDOWN_MIN мин вне допустимого диапазона (1–240). Пропуск."
fi

### === 12. Вывод результата ===
ROUTER_IP=$(ip -4 addr show br-lan 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1)
[ -z "$ROUTER_IP" ] && IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127\.0\.0\.1' | head -n1)

echo
echo "=== Готово! ==="
echo "Публичная шара: \\\\$ROUTER_IP\\$PUB_NAME   (доступна всем)"
echo "Приватная шара: \\\\$ROUTER_IP\\$PRIV_NAME  (требует логин $PRIV_USER)"
echo
echo "Диск: $MOUNT_POINT"
echo "================"

echo
echo "💡 Как подключиться к сетевым папкам (шарам) из Windows:"
echo "────────────────────────────────────────────────────────"
echo
echo "1️⃣  Добавь алиас «router» в файл hosts, чтобы Windows могла отличать подключения:"
echo "    Это нужно, потому что Windows не позволяет подключать к одному IP"
echo "    разные SMB-шары под разными пользователями (иначе выдаёт ошибку 1219)."
echo
echo "    🔧 Сделай это от имени администратора:"
echo "       Нажми ⊞ Win → введи 'cmd' → щёлкни правой кнопкой по 'Командная строка'"
echo "       → выбери 'Запуск от имени администратора'."
echo
echo "    Затем выполни команду:"
echo "       notepad C:\\Windows\\System32\\drivers\\etc\\hosts"
echo
echo "    В открывшемся файле добавь в конец строку:"
echo "       $IP router"
echo "    и сохрани изменения (Ctrl+S)."
echo
echo "2️⃣  Подключи SMB-шары из той же командной строки (cmd, не PowerShell):"
echo
echo "    Публичная шара (доступна всем):"
echo "       net use \\\\$IP\\rr /user:rr <пароль_пользователя_rr>"
echo
echo "    Приватная шара (для логина private_share_user):"
echo "       net use \\\\router\\private /user:private_share_user <пароль_пользователя_private_share_user>"
echo
echo "    💬 Пример:"
echo "       net use \\\\$IP\\rr /user:rr 123"
echo "       net use \\\\router\\private /user:private_share_user 1234567890"
echo
echo "    ⚠️ Важно:"
echo "       Команды 'net use' нужно вводить именно в классической 'Командной строке' (cmd),"
echo "       а не в PowerShell. В PowerShell символы '\\' иногда интерпретируются иначе."
echo
echo "3️⃣  После этого обе шары будут доступны в проводнике:"
echo "       \\\\$IP\\rr"
echo "       \\\\router\\private"
echo
echo "4️⃣  Если не вводить команды 'net use', Windows попытается использовать учётку"
echo "    текущего пользователя. Если имя или пароль не совпадут с пользователем SMB,"
echo "    появится ошибка:"
echo "       • 0x80070035 — «Не найден сетевой путь»"
echo "       • 0x80004005 — «Неопределённая ошибка»"
echo
echo "📘 Советы:"
echo "   • Чтобы првоерить старые подключения, можно выполнить:"
echo "         net use
echo "   • Чтобы удалить все старые подключения, можно выполнить:"
echo "         net use * /delete /y"
echo "   • Для автоподключения при старте Windows —"
echo "         добавь нужные команды 'net use' в автозагрузку или планировщик задач."
echo
