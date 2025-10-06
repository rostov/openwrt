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

### === 4. Проверяем, не смонтирован ли диск уже ===
EXIST_MNT=$(mount | grep -m1 "$DEV" | awk '{print $3}')
if [ -n "$EXIST_MNT" ]; then
    echo "[!] Диск уже смонтирован в $EXIST_MNT, размонтирую..."
    umount "$EXIST_MNT" || {
        echo "[x] Не удалось размонтировать $EXIST_MNT"
        exit 1
    }
fi

### === 5. Создание точки монтирования ===
mkdir -p "$MOUNT_POINT"
mountpoint -q "$MOUNT_POINT" || mount "$DEV" "$MOUNT_POINT"
if [ $? -ne 0 ]; then
    echo "[x] Не удалось смонтировать $DEV в $MOUNT_POINT"
    exit 1
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
ROUTER_IP=$(ip -4 addr show br-lan | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
[ -z "$ROUTER_IP" ] && IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127\.0\.0\.1' | head -n1)

echo
echo "=== Готово! ==="
echo "Публичная шара: \\\\$ROUTER_IP\\$PUB_NAME   (доступна всем)"
echo "Приватная шара: \\\\$ROUTER_IP\\$PRIV_NAME  (требует логин $PRIV_USER)"
echo
echo "Диск: $MOUNT_POINT"
echo "================"
