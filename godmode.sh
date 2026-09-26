#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# RAFZHOST - GOD MODE INSTALLER
# Pterodactyl Panel + Wings + Location + Node + Allocation + Egg
# Installer: pterodactyl-installer v1.3.0
# =========================================================

INSTALLER_BASE="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer"
INSTALLER_VERSION="v1.3.0"

PANEL_INSTALLER_URL="$INSTALLER_BASE/$INSTALLER_VERSION/installers/panel.sh"
WINGS_INSTALLER_URL="$INSTALLER_BASE/$INSTALLER_VERSION/installers/wings.sh"
LIB_URL="$INSTALLER_BASE/$INSTALLER_VERSION/lib/lib.sh"

LOG_FILE="/root/ptero_install.log"
WORK_DIR="/root/.rafz-ptero-installer"
RESULT_FILE="/root/rafzhost-panel-data.txt"

mkdir -p "$WORK_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

STEP="Inisialisasi"
LAST_ERROR=""

# ---------- error handler ----------
error_exit() {
    local rc=${1:-1}
    local msg="${2:-Unknown error}"
    LAST_ERROR="$msg"
    echo
    echo "========================================================="
    echo " INSTALLER GAGAL"
    echo "========================================================="
    echo "Step      : ${STEP:-Tidak diketahui}"
    echo "Exit code : $rc"
    echo "Pesan     : $msg"
    echo "Log       : $LOG_FILE"
    echo
    echo "20 baris terakhir log:"
    tail -20 "$LOG_FILE" 2>/dev/null || true
    echo "========================================================="
    exit "$rc"
}

trap 'rc=$?; error_exit "$rc" "Command gagal di step: ${STEP:-unknown}"' ERR

cleanup() {
    rm -f \
        "$WORK_DIR"/*.tmp \
        "$WORK_DIR"/*.php \
        "$WORK_DIR"/*.raw \
        /tmp/panel-install.sh \
        /tmp/wings-install.sh \
        /tmp/lib.sh \
        /tmp/egg.json \
        /tmp/egg_import.json \
        /tmp/rafz_egg.php \
        2>/dev/null || true
}
trap cleanup EXIT

banner() {
    echo "========================================================="
    printf ' %-55s\n' "$1"
    echo "========================================================="
}

ok()   { echo "[✓] $1"; }
info() { echo "[*] $1"; }
warn() { echo "[!] $1"; }

run_step() {
    STEP="$1"
    banner "$2"
}

# =========================================================
# ROOT CHECK
# =========================================================

if [[ $EUID -ne 0 ]]; then
    error_exit 1 "Installer wajib dijalankan sebagai root."
fi

# =========================================================
# NON INTERACTIVE
# =========================================================

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export DEBCONF_NONINTERACTIVE_SEEN=true
export COMPOSER_ALLOW_SUPERUSER=1

# =========================================================
# HEADER + INPUT
# =========================================================

banner "RAFZHOST x DEKZYMARKET - GOD MODE INSTALLER"

echo
echo "Masukkan konfigurasi domain dan akun Panel."
echo

printf "Domain Panel  : "
read -r PANEL_DOMAIN

printf "Domain Node   : "
read -r NODE_DOMAIN

printf "Email Admin   : "
read -r ADMIN_EMAIL

printf "Username Admin: "
read -r ADMIN_USERNAME

printf "Nama Depan    : "
read -r ADMIN_FIRSTNAME

printf "Nama Belakang : "
read -r ADMIN_LASTNAME

printf "Password Admin: "
read -rs ADMIN_PASSWORD
echo

# validasi input
[[ -n "$PANEL_DOMAIN" ]]    || error_exit 1 "Domain Panel tidak boleh kosong."
[[ -n "$NODE_DOMAIN" ]]     || error_exit 1 "Domain Node tidak boleh kosong."
[[ -n "$ADMIN_EMAIL" ]]     || error_exit 1 "Email Admin tidak boleh kosong."
[[ -n "$ADMIN_USERNAME" ]]  || error_exit 1 "Username Admin tidak boleh kosong."
[[ -n "$ADMIN_PASSWORD" ]]  || error_exit 1 "Password Admin tidak boleh kosong."
[[ "$PANEL_DOMAIN" != "$NODE_DOMAIN" ]] || error_exit 1 "Domain Panel dan Node tidak boleh sama."

# simple email check
if [[ ! "\( ADMIN_EMAIL" =\~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,} \) ]]; then
    error_exit 1 "Format email admin tidak valid."
fi

# =========================================================
# DEFAULT CONFIG
# =========================================================

LOCATION_SHORT="RafzHost"
LOCATION_LONG="RAFZHOST Indonesia"

NODE_NAME="RAFZHOST-NODE-01"
NODE_DESCRIPTION="RAFZHOST Pterodactyl Node"

ALLOCATION_START="2000"
ALLOCATION_END="2999"

DAEMON_PORT="8080"
SFTP_PORT="2022"

MEMORY_OVERALLOCATE="0"
DISK_OVERALLOCATE="0"
UPLOAD_SIZE="100"

EGG_NEST_NAME="Bot NodeJS"

echo
info "Location : $LOCATION_SHORT"
info "Node     : $NODE_NAME"
info "Ports    : $ALLOCATION_START-$ALLOCATION_END"
info "Nest     : $EGG_NEST_NAME"
echo

# =========================================================
# 01 SYSTEM
# =========================================================

run_step "01" "[01] Pengecekan sistem"

. /etc/os-release

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64|aarch64|arm64) ;;
    *) error_exit 1 "Architecture tidak didukung: $ARCH" ;;
esac

case "$ID:$VERSION_ID" in
    ubuntu:22.04|ubuntu:24.04|debian:11|debian:12|debian:13) ;;
    *)
        echo "OS belum divalidasi:"
        echo "$PRETTY_NAME"
        error_exit 1 "OS tidak didukung"
        ;;
esac

echo "OS          : $ID $VERSION_ID"
echo "Architecture: $ARCH"
ok "OS dan architecture terdeteksi."

# =========================================================
# 02 DEPENDENCY
# =========================================================

run_step "02" "[02] Install dependency dasar"

apt-get update --allow-releaseinfo-change -y || error_exit 1 "apt-get update gagal"

apt-get install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    jq \
    unzip \
    git \
    redis-server \
    openssl \
    dnsutils \
    lsof \
    python3 \
    || error_exit 1 "Gagal install dependency dasar"

ok "Dependency dasar siap."

# =========================================================
# 03 PUBLIC IP
# =========================================================

run_step "03" "[03] Deteksi IP VPS"

PUBLIC_IP="$(
    curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true
)"

if [[ ! "\( PUBLIC_IP" =\~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ \) ]]; then
    PUBLIC_IP="$(hostname -I | awk '{print $1}')"
fi

[[ "\( PUBLIC_IP" =\~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ \) ]] || error_exit 1 "IPv4 VPS tidak ditemukan."

echo "VPS IPv4: $PUBLIC_IP"
ok "IP terdeteksi."

# =========================================================
# 04 DNS
# =========================================================

run_step "04" "[04] Pengecekan DNS"

PANEL_DNS="$(dig +short A "$PANEL_DOMAIN" 2>/dev/null | tail -1 || true)"
NODE_DNS="$(dig +short A "$NODE_DOMAIN" 2>/dev/null | tail -1 || true)"

echo "Panel DNS : ${PANEL_DNS:-TIDAK ADA}"
echo "Node DNS  : ${NODE_DNS:-TIDAK ADA}"

if [[ "$PANEL_DNS" != "$PUBLIC_IP" ]]; then
    echo
    echo "DNS Panel belum mengarah ke VPS."
    echo "Domain : $PANEL_DOMAIN"
    echo "DNS    : ${PANEL_DNS:-NONE}"
    echo "VPS    : $PUBLIC_IP"
    error_exit 1 "DNS Panel tidak match"
fi

if [[ "$NODE_DNS" != "$PUBLIC_IP" ]]; then
    echo
    echo "DNS Node belum mengarah ke VPS."
    echo "Domain : $NODE_DOMAIN"
    echo "DNS    : ${NODE_DNS:-NONE}"
    echo "VPS    : $PUBLIC_IP"
    error_exit 1 "DNS Node tidak match"
fi

ok "DNS terdeteksi dan sesuai IP VPS."

# =========================================================
# 05 PANEL
# =========================================================

run_step "05" "[05] Install Pterodactyl Panel"

DB_PASSWORD="$(openssl rand -hex 24)"

export FQDN="$PANEL_DOMAIN"
export MYSQL_DB="panel"
export MYSQL_USER="pterodactyl"
export MYSQL_PASSWORD="$DB_PASSWORD"
export timezone="Asia/Jakarta"
export telemetry="false"
export ASSUME_SSL="true"
export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_FIREWALL="true"
export email="$ADMIN_EMAIL"
export user_email="$ADMIN_EMAIL"
export user_username="$ADMIN_USERNAME"
export user_firstname="${ADMIN_FIRSTNAME:-Rafz}"
export user_lastname="${ADMIN_LASTNAME:-Host}"
export user_password="$ADMIN_PASSWORD"

info "Mengambil installer resmi community installer $INSTALLER_VERSION..."

curl -fsSL "$LIB_URL" -o /tmp/lib.sh || error_exit 1 "Gagal download lib.sh"
curl -fsSL "$PANEL_INSTALLER_URL" -o /tmp/panel-install.sh || error_exit 1 "Gagal download panel installer"

chmod +x /tmp/panel-install.sh
# shellcheck source=/dev/null
source /tmp/lib.sh

info "Menjalankan installer Panel..."

set +e
bash /tmp/panel-install.sh 2>&1
PANEL_RC=$?
set -e

if [[ $PANEL_RC -ne 0 || ! -f /var/www/pterodactyl/artisan ]]; then
    error_exit 1 "Panel tidak terpasang dengan benar (rc=$PANEL_RC)"
fi

rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

cd /var/www/pterodactyl
php artisan optimize:clear >/dev/null 2>&1 || true
chown -R www-data:www-data /var/www/pterodactyl

systemctl enable --now nginx 2>/dev/null || true
systemctl enable --now mariadb 2>/dev/null || true
systemctl enable --now redis-server 2>/dev/null || true

if [[ -f /etc/systemd/system/pteroq.service ]]; then
    systemctl enable --now pteroq 2>/dev/null || true
fi

nginx -t || error_exit 1 "nginx config test gagal"
systemctl restart nginx || error_exit 1 "gagal restart nginx"

php artisan --version || error_exit 1 "php artisan gagal"

systemctl is-active --quiet nginx   || error_exit 1 "Nginx tidak aktif"
systemctl is-active --quiet mariadb || error_exit 1 "MariaDB tidak aktif"

ok "Panel terpasang dan service utama aktif."

# =========================================================
# 06 WINGS
# =========================================================

run_step "06" "[06] Install Wings"

export FQDN="$NODE_DOMAIN"
export EMAIL="$ADMIN_EMAIL"
export CONFIGURE_FIREWALL="true"
export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_DBHOST="false"

curl -fsSL "$WINGS_INSTALLER_URL" -o /tmp/wings-install.sh || error_exit 1 "Gagal download wings installer"
chmod +x /tmp/wings-install.sh

# shellcheck source=/dev/null
source /tmp/lib.sh

info "Menjalankan installer Wings..."

set +e
bash /tmp/wings-install.sh 2>&1
WINGS_RC=$?
set -e

if [[ $WINGS_RC -ne 0 || ! -x /usr/local/bin/wings ]]; then
    error_exit 1 "Wings gagal dipasang (rc=$WINGS_RC)"
fi

systemctl daemon-reload
systemctl enable wings >/dev/null 2>&1 || true

ok "Wings binary dan service terpasang."

# =========================================================
# 07 CREATE PLTA / PLTC
# =========================================================

run_step "07" "[07] Membuat PLTA / PLTC"

cat > "$WORK_DIR/create_keys.php" <<'PHP'
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$user = \Pterodactyl\Models\User::where('root_admin', 1)->first();
if (!$user) {
    fwrite(STDERR, "NO_ADMIN\n");
    exit(1);
}

$service = app(\Pterodactyl\Services\Api\KeyCreationService::class);

$appKey = $service
    ->setKeyType(\Pterodactyl\Models\ApiKey::TYPE_APPLICATION)
    ->handle(
        [
            'user_id' => $user->id,
            'memo' => 'RAFZHOST Auto PLTA',
            'allowed_ips' => [],
        ],
        [
            'r_locations' => 3,
            'r_nodes' => 3,
            'r_allocations' => 3,
            'r_nests' => 3,
            'r_eggs' => 3,
            'r_servers' => 3,
            'r_users' => 3,
            'r_database_hosts' => 3,
            'r_server_databases' => 3,
        ]
    );

$accountKey = $service
    ->setKeyType(\Pterodactyl\Models\ApiKey::TYPE_ACCOUNT)
    ->handle(
        [
            'user_id' => $user->id,
            'memo' => 'RAFZHOST Auto PLTC',
            'allowed_ips' => [],
        ]
    );

echo "ADMIN_ID={$user->id}\n";
echo 'PLTA=' . $appKey->identifier . decrypt($appKey->token) . "\n";
echo 'PLTC=' . $accountKey->identifier . decrypt($accountKey->token) . "\n";
PHP

set +e
KEY_OUTPUT="$(cd /var/www/pterodactyl && php "$WORK_DIR/create_keys.php" 2>&1)"
KEY_RC=$?
set -e

if [[ $KEY_RC -ne 0 ]]; then
    echo "$KEY_OUTPUT"
    error_exit 1 "Gagal membuat API key (PLTA/PLTC)"
fi

echo "$KEY_OUTPUT"

PLTA="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^PLTA=//p' | head -1)"
PLTC="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^PLTC=//p' | head -1)"
ADMIN_ID="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^ADMIN_ID=//p' | head -1)"

[[ "$PLTA" == ptla_* ]] || error_exit 1 "PLTA gagal dibuat / format salah"

if [[ "$PLTC" == ptlc_* ]]; then
    ok "PLTC berhasil dibuat."
else
    warn "PLTC gagal dibuat, proses tetap dilanjutkan."
fi

ok "PLTA berhasil dibuat."

# =========================================================
# 08 API HELPER
# =========================================================

run_step "08" "[08] Menyiapkan Application API"

API_BASE="https://$PANEL_DOMAIN/api/application"

API_HEADERS=(
    -H "Authorization: Bearer $PLTA"
    -H "Accept: Application/vnd.pterodactyl.v1+json"
    -H "Content-Type: application/json"
)

api_get() {
    local url="$1"
    local out
    set +e
    out="\( (curl -fsS --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 60 " \){API_HEADERS[@]}" "$url" 2>&1)"
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "$out" >&2
        return $rc
    fi
    printf '%s' "$out"
}

api_post() {
    local url="$1"
    local data="$2"
    local out
    set +e
    out="\( (curl -fsS --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 60 " \){API_HEADERS[@]}" -X POST -d "$data" "$url" 2>&1)"
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "$out" >&2
        return $rc
    fi
    printf '%s' "$out"
}

api_error() {
    local body="$1"
    echo "$body" | jq -r '.errors[]?.detail // .message // empty' 2>/dev/null | paste -sd ' | ' - || echo "$body"
}

set +e
LOCATIONS_JSON="$(api_get "$API_BASE/locations?per_page=100")"
LOC_RC=$?
set -e

if [[ $LOC_RC -ne 0 ]]; then
    error_exit 1 "PLTA tidak bisa mengakses Application API"
fi

ok "Application API dapat diakses."

# =========================================================
# 09 LOCATION
# =========================================================

run_step "09" "[09] Membuat Location"

LOCATION_ID="$(
    printf '%s' "$LOCATIONS_JSON" |
    jq -r --arg short "$LOCATION_SHORT" '
        .data[]
        | select(.attributes.short == $short)
        | .attributes.id
    ' | head -1
)"

if [[ -n "$LOCATION_ID" && "$LOCATION_ID" != "null" ]]; then
    ok "Location sudah ada. ID: $LOCATION_ID"
else
    LOCATION_BODY="$(
        jq -nc \
            --arg short "$LOCATION_SHORT" \
            --arg long "$LOCATION_LONG" \
            '{ short: $short, long: $long }'
    )"

    set +e
    LOC_CREATE_RAW="$(api_post "$API_BASE/locations" "$LOCATION_BODY" 2>&1)"
    LOC_RC=$?
    set -e

    if [[ $LOC_RC -ne 0 ]]; then
        echo
        echo "API Location gagal:"
        api_error "$LOC_CREATE_RAW"

        LOCATIONS_JSON="$(api_get "$API_BASE/locations?per_page=100" 2>/dev/null || true)"
        LOCATION_ID="$(
            printf '%s' "$LOCATIONS_JSON" |
            jq -r --arg short "$LOCATION_SHORT" '
                .data[]
                | select(.attributes.short == $short)
                | .attributes.id
            ' | head -1
        )"

        if [[ -n "$LOCATION_ID" && "$LOCATION_ID" != "null" ]]; then
            ok "Location ternyata sudah dibuat. ID: $LOCATION_ID"
        else
            error_exit 1 "Gagal membuat Location"
        fi
    else
        LOCATION_ID="$(
            printf '%s' "$LOC_CREATE_RAW" |
            jq -r '.attributes.id // .data.attributes.id // empty'
        )"
        [[ -n "$LOCATION_ID" ]] || error_exit 1 "Location ID kosong setelah create"
        ok "Location berhasil dibuat. ID: $LOCATION_ID"
    fi
fi

# =========================================================
# 10 NODE
# =========================================================

run_step "10" "[10] Membuat Node"

NODES_JSON="$(api_get "$API_BASE/nodes?per_page=100")" || error_exit 1 "Gagal ambil list nodes"

NODE_ID="$(
    printf '%s' "$NODES_JSON" |
    jq -r --arg fqdn "$NODE_DOMAIN" '
        .data[]
        | select(.attributes.fqdn == $fqdn)
        | .attributes.id
    ' | head -1
)"

RAM_MB="$(free -m | awk 'NR==2{print $2}')"
DISK_MB="$(df -BM / | awk 'NR==2{gsub(/M/,""); print $4}')"

(( RAM_MB > 512 ))  && RAM_MB=$((RAM_MB - 512))
(( DISK_MB > 3072 )) && DISK_MB=$((DISK_MB - 3072))

if [[ -n "$NODE_ID" && "$NODE_ID" != "null" ]]; then
    ok "Node sudah ada. ID: $NODE_ID"
else
    NODE_BODY="$(
        jq -nc \
            --arg name "$NODE_NAME" \
            --arg desc "$NODE_DESCRIPTION" \
            --argjson location_id "$LOCATION_ID" \
            --arg fqdn "$NODE_DOMAIN" \
            --argjson memory "$RAM_MB" \
            --argjson disk "$DISK_MB" \
            --argjson upload "$UPLOAD_SIZE" \
            --argjson sftp "$SFTP_PORT" \
            --argjson listen "$DAEMON_PORT" \
            --argjson mo "$MEMORY_OVERALLOCATE" \
            --argjson do "$DISK_OVERALLOCATE" \
            '{
                name: $name,
                description: $desc,
                location_id: $location_id,
                fqdn: $fqdn,
                scheme: "https",
                behind_proxy: false,
                public: true,
                daemon_base: "/var/lib/pterodactyl/volumes",
                memory: $memory,
                memory_overallocate: $mo,
                disk: $disk,
                disk_overallocate: $do,
                upload_size: $upload,
                daemon_sftp: $sftp,
                daemon_listen: $listen,
                maintenance_mode: false
            }'
    )"

    set +e
    NODE_CREATE_RAW="$(api_post "$API_BASE/nodes" "$NODE_BODY" 2>&1)"
    NODE_RC=$?
    set -e

    if [[ $NODE_RC -ne 0 ]]; then
        echo
        echo "API Node gagal:"
        api_error "$NODE_CREATE_RAW"

        NODES_JSON="$(api_get "$API_BASE/nodes?per_page=100" 2>/dev/null || true)"
        NODE_ID="$(
            printf '%s' "$NODES_JSON" |
            jq -r --arg fqdn "$NODE_DOMAIN" '
                .data[]
                | select(.attributes.fqdn == $fqdn)
                | .attributes.id
            ' | head -1
        )"

        if [[ -n "$NODE_ID" && "$NODE_ID" != "null" ]]; then
            ok "Node ternyata sudah dibuat. ID: $NODE_ID"
        else
            error_exit 1 "Gagal membuat Node"
        fi
    else
        NODE_ID="$(
            printf '%s' "$NODE_CREATE_RAW" |
            jq -r '.attributes.id // .data.attributes.id // empty'
        )"
        [[ -n "$NODE_ID" ]] || error_exit 1 "Node ID kosong setelah create"
        ok "Node berhasil dibuat. ID: $NODE_ID"
    fi
fi

# =========================================================
# 11 ALLOCATION
# =========================================================

run_step "11" "[11] Membuat Allocation"

ALLOC_JSON="$(api_get "$API_BASE/nodes/$NODE_ID/allocations?per_page=100")" || error_exit 1 "Gagal ambil allocation"

EXISTING_PORT="$(
    printf '%s' "$ALLOC_JSON" |
    jq -r --arg ip "$PUBLIC_IP" --argjson p "$ALLOCATION_START" '
        .data[]
        | select(.attributes.ip == $ip and .attributes.port == $p)
        | .attributes.port
    ' | head -1
)"

if [[ "$EXISTING_PORT" == "$ALLOCATION_START" ]]; then
    ok "Allocation $ALLOCATION_START sudah ada."
else
    ALLOC_BODY="$(
        jq -nc \
            --arg ip "$PUBLIC_IP" \
            --arg alias "$NODE_NAME" \
            --arg ports "$ALLOCATION_START-$ALLOCATION_END" \
            '{ ip: $ip, alias: $alias, ports: [$ports] }'
    )"

    set +e
    ALLOC_RAW="$(api_post "$API_BASE/nodes/$NODE_ID/allocations" "$ALLOC_BODY" 2>&1)"
    ALLOC_RC=$?
    set -e

    if [[ $ALLOC_RC -ne 0 ]]; then
        echo
        echo "API Allocation gagal:"
        api_error "$ALLOC_RAW"
        error_exit 1 "Gagal membuat Allocation"
    fi

    CREATED_COUNT="$(printf '%s' "$ALLOC_RAW" | jq '.data | length' 2>/dev/null || echo 0)"
    ok "Allocation berhasil dibuat: $CREATED_COUNT port."
fi

# =========================================================
# 12 WINGS CONFIG
# =========================================================

run_step "12" "[12] Mengambil konfigurasi Wings dari Panel"

CONFIG_RAW="$WORK_DIR/node-config.raw"
CONFIG_YML="/etc/pterodactyl/config.yml"

mkdir -p /etc/pterodactyl

curl -fsS \
    --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 60 \
    -H "Authorization: Bearer $PLTA" \
    -H "Accept: text/yaml, text/plain, application/vnd.pterodactyl.v1+json" \
    "$API_BASE/nodes/$NODE_ID/configuration" \
    -o "$CONFIG_RAW" || error_exit 1 "Gagal ambil config wings dari panel"

if grep -qE '^[[:space:]]*(debug|uuid|token_id|token|api|system|remote):' "$CONFIG_RAW"; then
    cp "$CONFIG_RAW" "$CONFIG_YML"
elif jq -e . "$CONFIG_RAW" >/dev/null 2>&1; then
    if jq -e '.attributes' "$CONFIG_RAW" >/dev/null 2>&1; then
        jq -r '.attributes' "$CONFIG_RAW" > "$CONFIG_YML"
    else
        jq -r . "$CONFIG_RAW" > "$CONFIG_YML"
    fi
else
    echo
    echo "Format konfigurasi Wings tidak dikenali:"
    head -40 "$CONFIG_RAW"
    error_exit 1 "Format config wings tidak valid"
fi

[[ -s "$CONFIG_YML" ]] || error_exit 1 "config.yml kosong"

chmod 600 "$CONFIG_YML"
chown root:root "$CONFIG_YML"

ok "config.yml berhasil ditulis."

# =========================================================
# 13 START WINGS
# =========================================================

run_step "13" "[13] Menjalankan Wings"

systemctl daemon-reload
systemctl enable wings >/dev/null 2>&1 || true
systemctl restart wings || error_exit 1 "Gagal restart wings"

sleep 3

if ! systemctl is-active --quiet wings; then
    echo
    echo "Wings tidak aktif."
    echo
    echo "===== WINGS LOG ====="
    journalctl -u wings -n 50 --no-pager || true
    echo "====================="
    error_exit 1 "Wings gagal start"
fi

ok "Wings aktif."

# =========================================================
# 14 FINAL VALIDATION
# =========================================================

run_step "14" "[14] Validasi akhir"

cd /var/www/pterodactyl
php artisan optimize:clear >/dev/null 2>&1 || true
chown -R www-data:www-data /var/www/pterodactyl

systemctl restart pteroq >/dev/null 2>&1 || true
systemctl restart nginx >/dev/null 2>&1 || true

echo
echo "===== SERVICE STATUS ====="
echo "Nginx    : $(systemctl is-active nginx || true)"
echo "MariaDB  : $(systemctl is-active mariadb || true)"
echo "Redis    : $(systemctl is-active redis-server || true)"
echo "Pteroq   : $(systemctl is-active pteroq || true)"
echo "Wings    : $(systemctl is-active wings || true)"

echo
echo "===== HTTP CHECK ====="
curl -ksS --max-time 15 -o /dev/null -w 'Panel HTTP : %{http_code}\n' "https://$PANEL_DOMAIN" || true
curl -ksS --max-time 15 -o /dev/null -w 'Node HTTP  : %{http_code}\n' "https://$NODE_DOMAIN:$DAEMON_PORT/api/system" || true

# =========================================================
# 15 IMPORT EGG (pakai yang lu kasih)
# =========================================================

run_step "15" "[15] Import Egg — Nusantara Project GOD MODE"

info "Menulis egg.json..."

cat > /tmp/egg.json << 'EGGJSON'
{
    "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO",
    "meta": {
        "version": "PTDL_v2",
        "update_url": null
    },
    "exported_at": "2026-08-24T06:34:06+07:00",
    "name": "Nusantara Project - ULTIMATE GOD MODE (Unified)",
    "author": "rafzhost@rafzhost.my.id",
    "description": "Satu Egg untuk menguasai semuanya. Bisa switch antara YARN / NPM langsung dari panel. Dilengkapi auto-bypass Baileys error, full image Docker (Node 15-24, Python, OS), Cloudflared Tunnel, dan UI Custom Bahasa Indonesia lengkap.",
    "features": [],
    "docker_images": {
        "NodeJS 24": "ghcr.io/parkervcp/yolks:nodejs_24",
        "NodeJS 23": "ghcr.io/parkervcp/yolks:nodejs_23",
        "NodeJS 22": "ghcr.io/parkervcp/yolks:nodejs_22",
        "NodeJS 21": "ghcr.io/parkervcp/yolks:nodejs_21",
        "NodeJS 20": "ghcr.io/parkervcp/yolks:nodejs_20",
        "NodeJS 19": "ghcr.io/parkervcp/yolks:nodejs_19",
        "NodeJS 18": "ghcr.io/parkervcp/yolks:nodejs_18",
        "NodeJS 17": "ghcr.io/parkervcp/yolks:nodejs_17",
        "NodeJS 16": "ghcr.io/parkervcp/yolks:nodejs_16",
        "NodeJS 15": "ghcr.io/parkervcp/yolks:nodejs_15",
        "Python 3.12": "ghcr.io/parkervcp/yolks:python_3.12",
        "Python 3.11": "ghcr.io/parkervcp/yolks:python_3.11",
        "Python 3.10": "ghcr.io/parkervcp/yolks:python_3.10",
        "Python 3.9": "ghcr.io/parkervcp/yolks:python_3.9",
        "Python 3.8": "ghcr.io/parkervcp/yolks:python_3.8",
        "Debian OS (Universal)": "ghcr.io/parkervcp/yolks:debian",
        "Ubuntu OS (Universal)": "ghcr.io/parkervcp/yolks:ubuntu"
    },
    "file_denylist": [],
    "startup": "if [[ -d .git ]] && [[ \"{{AUTO_UPDATE}}\" == \"1\" ]]; then git pull; fi; if [[ ! -z ${CLOUDFLARED_TOKEN} ]]; then echo \"Memulai Cloudflared Tunnel...\"; wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O cloudflared && chmod +x cloudflared && ./cloudflared tunnel --no-autoupdate run --token \( {CLOUDFLARED_TOKEN} > /dev/null 2>&1 & fi; req_file= \){REQUIREMENTS_FILE:-requirements.txt}; if [ -f /home/container/$req_file ]; then pip install -r \( req_file; fi; if [ \" \){PACKAGE_MANAGER}\" == \"npm\" ]; then if [[ ! -z ${NODE_PACKAGES} ]]; then yes \"\" | npm install ${NODE_PACKAGES} --legacy-peer-deps --no-fund --no-audit; fi; if [[ ! -z ${UNNODE_PACKAGES} ]]; then yes \"\" | npm uninstall ${UNNODE_PACKAGES} --no-fund --no-audit; fi; if [ -f /home/container/package.json ]; then yes \"\" | npm install --legacy-peer-deps --no-fund --no-audit; fi; rm -rf .npm .log .cache --force; else if [[ ! -z ${NODE_PACKAGES} ]]; then yes | yarn add ${NODE_PACKAGES} --non-interactive --ignore-engines; fi; if [[ ! -z ${UNNODE_PACKAGES} ]]; then yes | yarn remove ${UNNODE_PACKAGES} --non-interactive; fi; if [ -f /home/container/package.json ]; then yes | yarn install --non-interactive --ignore-engines; fi; rm -rf .npm .log .cache .yarn-cache --force; fi; if [[ ! -z \( {CUSTOM_ENVIRONMENT_VARIABLES} ]]; then vars= \)(echo ${CUSTOM_ENVIRONMENT_VARIABLES} | tr \";\" \"\\n\"); for line in $vars; do export $line; done fi; eval ${CMD_RUN};",
    "config": {
        "files": "{}",
        "startup": "{\r\n    \"done\": \"running\"\r\n}",
        "logs": "{}",
        "stop": "^^C"
    },
    "scripts": {
        "installation": {
            "script": "#!/bin/bash\n# God Mode Installation Script (Unified Yarn/NPM) + Custom UI\napt update\napt install -y git curl wget jq file unzip make gcc g++ python3 python3-dev python3-pip libtool\n\n# Cek dan install yarn secara default untuk fallback\nif command -v npm &> /dev/null; then npm install -g yarn; fi\n\nmkdir -p /mnt/server\ncd /mnt/server\n\nif [ \"\( {USER_UPLOAD}\" == \"true\" ] || [ \" \){USER_UPLOAD}\" == \"1\" ]; then\n    echo -e \"assuming user knows what they are doing have a good day.\"\n    exit 0\nfi\n\nif [[ \( {GIT_ADDRESS} != *.git ]]; then\n    GIT_ADDRESS= \){GIT_ADDRESS}.git\nfi\n\nif [ -z \"\( {USERNAME}\" ] && [ -z \" \){ACCESS_TOKEN}\" ]; then\n    echo -e \"using anon api call\"\nelse\n    GIT_ADDRESS=\"https://\( {USERNAME}: \){ACCESS_TOKEN}@$(echo -e \( {GIT_ADDRESS} | cut -d/ -f3-)\"\nfi\n\nif [ \" \)(ls -A /mnt/server)\" ]; then\n    if [ -d .git ]; then\n        if [ -f .git/config ]; then\n            ORIGIN=\( (git config --get remote.origin.url)\n        else\n            exit 10\n        fi\n    fi\n    if [ \" \){ORIGIN}\" == \"${GIT_ADDRESS}\" ]; then git pull; fi\nelse\n    if [ -z ${BRANCH} ]; then\n        git clone ${GIT_ADDRESS} .\n    else\n        git clone --single-branch --branch ${BRANCH} \( {GIT_ADDRESS} .\n    fi\nfi\n\necho \"Mengecek dependencies nodejs...\"\nif [ -f /mnt/server/package.json ]; then\n    if [ \" \){PACKAGE_MANAGER}\" == \"npm\" ]; then\n        echo \"--> Menjalankan instalasi menggunakan NPM (Mode: legacy-peer-deps)\"\n        rm -rf node_modules package-lock.json\n        yes \"\" | npm install --production --legacy-peer-deps --no-fund --no-audit\n    else\n        echo \"--> Menjalankan instalasi menggunakan YARN (Mode: ignore-engines)\"\n        rm -f package-lock.json\n        yes | yarn install --production --non-interactive --ignore-engines\n    fi\nfi\n\nreq_file=${REQUIREMENTS_FILE:-requirements.txt}\nif [ -f /mnt/server/$req_file ]; then\n    echo \"--> Menginstal library Python dari $req_file...\"\n    pip install -r $req_file\nfi\n\necho -e \"install complete\"\nexit 0",
            "container": "debian:bullseye-slim",
            "entrypoint": "bash"
        }
    },
    "variables": [
        {
            "name": "GUNAKAN FILE UPLOAD MANUAL?",
            "description": "Aktifkan saklar ini jika Anda mengupload file bot sendiri secara manual. Matikan saklar ini jika Anda ingin mendownload script otomatis dari GitHub. PENTING: Mode download dari GitHub HANYA akan terpicu jika Anda menekan tombol \"Reinstall Server\" di menu Settings (paling bawah).",
            "env_variable": "USER_UPLOAD",
            "default_value": "1",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|boolean",
            "field_type": "text"
        },
        {
            "name": "PACKAGE MANAGER (YARN / NPM)",
            "description": "Pilih package manager yang ingin digunakan untuk menginstal modul NodeJS (ketik 'yarn' atau 'npm'). Default direkomendasikan menggunakan yarn untuk menghindari error EALLOWGIT dari Baileys/GitHub.",
            "env_variable": "PACKAGE_MANAGER",
            "default_value": "yarn",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string|in:yarn,npm",
            "field_type": "text"
        },
        {
            "name": "FILE UTAMA SCRIPT (ENTRY FILE)",
            "description": "Nama file utama yang bertugas menyalakan bot Anda. Pastikan disesuaikan dengan package manager pilihan Anda. Contoh: yarn start, npm start, python main.py",
            "env_variable": "CMD_RUN",
            "default_value": "yarn start",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|string",
            "field_type": "text"
        },
        {
            "name": "FILE LIBRARY / REQUIREMENTS",
            "description": "Nama file yang berisi daftar library yang dibutuhkan script (standarnya requirements.txt). Server akan mendeteksi dan menginstalnya secara otomatis jika file ini ditemukan.",
            "env_variable": "REQUIREMENTS_FILE",
            "default_value": "requirements.txt",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "LINK REPOSITORI GIT (OPSIONAL)",
            "description": "Alamat link Repository GitHub (contoh: https://github.com/username/nama_repo). PENTING: Agar aksi Anda dalam mengisi/mengubah link Repository Github di kolom ini dapat terpicu, Anda WAJIB menekan tombol \"Reinstall Server\" di menu Settings (paling bawah) agar sistem mengunduhnya. Jika Anda tidak melakukannya, tidak akan ada yang terjadi.",
            "env_variable": "GIT_ADDRESS",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Install Branch",
            "description": "The branch to install.",
            "env_variable": "BRANCH",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Auto Update",
            "description": "Pull the latest files dari Git pas server start (1 = Yes, 0 = No)",
            "env_variable": "AUTO_UPDATE",
            "default_value": "1",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|boolean",
            "field_type": "text"
        },
        {
            "name": "Cloudflared Token",
            "description": "Token untuk Cloudflare Argo Tunnel. Kalo diisi, panel bakal otomatis download & run Cloudflared di background buat web/bot lu.",
            "env_variable": "CLOUDFLARED_TOKEN",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Git Username",
            "description": "Username to auth with git.",
            "env_variable": "USERNAME",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Git Access Token",
            "description": "Password/Token to use with git.",
            "env_variable": "ACCESS_TOKEN",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        }
    ]
}
EGGJSON

# validasi json
python3 -c '
import json, sys
with open("/tmp/egg.json") as f:
    d = json.load(f)
startup_len = len(d.get("startup", ""))
vars_count  = len(d.get("variables", []))
if startup_len == 0:
    print("EGG_STARTUP_EMPTY")
    sys.exit(1)
print(f"EGG_OK startup={startup_len} vars={vars_count}")
' || error_exit 1 "egg.json tidak valid"

info "Menulis PHP importer..."

cat > /tmp/rafz_egg.php << 'PHP'
<?php
require "/var/www/pterodactyl/vendor/autoload.php";
$app = require_once "/var/www/pterodactyl/bootstrap/app.php";
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

$eggData = json_decode(file_get_contents("/tmp/egg.json"), true);
if (!$eggData) {
    echo "EGG_JSON_ERROR\n";
    exit(1);
}

$nestName = "bot";
$nest = \Pterodactyl\Models\Nest::where("name", $nestName)->first();
if (!$nest) {
    $nest = new \Pterodactyl\Models\Nest();
    $nest->author = "admin@gmail.com";
    $nest->name = $nestName;
    $nest->description = "Bot eggs";
    $nest->save();
}
$nestId = (int) $nest->id;
echo "NEST_ID=" . $nestId . "\n";

// hapus egg lama biar ga duplikat
\Pterodactyl\Models\Egg::where("nest_id", $nestId)
    ->where("name", $eggData["name"] ?? "")
    ->delete();

// 1) coba EggImporterService resmi
try {
    $tmp = "/tmp/egg_import.json";
    file_put_contents($tmp, json_encode($eggData, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
    $file = new \Illuminate\Http\UploadedFile($tmp, "egg.json", "application/json", null, true);
    $egg = app(\Pterodactyl\Services\Eggs\Sharing\EggImporterService::class)->handle($file, $nestId);
    echo "EGG_ID=" . $egg->id . "\n";
    echo "IMPORT_METHOD=service\n";
    exit(0);
} catch (Throwable $e) {
    echo "SERVICE_IMPORT_FAIL=" . $e->getMessage() . "\n";
}

// 2) fallback manual
$norm = function ($v, $default = []) {
    if ($v === null) return $default;
    if (is_string($v)) {
        $d = json_decode($v, true);
        return $d === null ? $default : $d;
    }
    return (is_array($v) || is_object($v)) ? $v : $default;
};

$egg = new \Pterodactyl\Models\Egg();
$egg->uuid = (string) Illuminate\Support\Str::uuid();
$egg->nest_id = $nestId;
$egg->author = $eggData["author"] ?? "admin@gmail.com";
$egg->name = $eggData["name"] ?? "Imported Egg";
$egg->description = $eggData["description"] ?? "";
$egg->features = $norm($eggData["features"] ?? [], []);
$egg->docker_images = $norm($eggData["docker_images"] ?? [], ["NodeJS 18" => "ghcr.io/parkervcp/yolks:nodejs_18"]);
$egg->file_denylist = $norm($eggData["file_denylist"] ?? [], []);
$egg->startup = $eggData["startup"] ?? "node index.js";
$cfg = is_array($eggData["config"] ?? null) ? $eggData["config"] : [];
$egg->config_files = $norm($cfg["files"] ?? new stdClass(), new stdClass());
$egg->config_startup = $norm($cfg["startup"] ?? new stdClass(), new stdClass());
$egg->config_logs = $norm($cfg["logs"] ?? new stdClass(), new stdClass());
$egg->config_stop = $cfg["stop"] ?? "stop";
$egg->script_container = $eggData["scripts"]["installation"]["container"] ?? "debian:bullseye-slim";
$egg->script_entry = $eggData["scripts"]["installation"]["entrypoint"] ?? "bash";
$egg->script_install = $eggData["scripts"]["installation"]["script"] ?? "";
$egg->script_is_privileged = true;
$egg->force_outgoing_ip = false;
$egg->save();

foreach (($eggData["variables"] ?? []) as $v) {
    if (empty($v["env_variable"])) continue;
    $var = new \Pterodactyl\Models\EggVariable();
    $var->egg_id = $egg->id;
    $var->name = $v["name"] ?? $v["env_variable"];
    $var->description = $v["description"] ?? "";
    $var->env_variable = $v["env_variable"];
    $var->default_value = $v["default_value"] ?? "";
    $var->user_viewable = !empty($v["user_viewable"]);
    $var->user_editable = !empty($v["user_editable"]);
    $var->rules = $v["rules"] ?? "nullable|string";
    $var->save();
}

echo "EGG_ID=" . $egg->id . "\n";
echo "IMPORT_METHOD=manual\n";
PHP

info "Menjalankan PHP importer..."

set +e
EGG_OUTPUT="$(cd /var/www/pterodactyl && php /tmp/rafz_egg.php 2>&1)"
EGG_RC=$?
set -e

echo "$EGG_OUTPUT"

EGG_ID="$(printf '%s\n' "$EGG_OUTPUT" | sed -n 's/^EGG_ID=//p' | head -1)"
NEST_ID="$(printf '%s\n' "$EGG_OUTPUT" | sed -n 's/^NEST_ID=//p' | head -1)"
IMPORT_METHOD="$(printf '%s\n' "$EGG_OUTPUT" | sed -n 's/^IMPORT_METHOD=//p' | head -1)"

if [[ -z "$EGG_ID" || "$EGG_ID" == "0" ]]; then
    echo
    echo "Egg import gagal. Output PHP:"
    echo "$EGG_OUTPUT"
    error_exit 1 "Egg import gagal"
fi

ok "Egg berhasil diimport. ID: $EGG_ID  Nest ID: $NEST_ID  Metode: $IMPORT_METHOD"

info "Membersihkan cache Panel..."

cd /var/www/pterodactyl
php artisan config:clear >/dev/null 2>&1 || true
php artisan cache:clear  >/dev/null 2>&1 || true
php artisan view:clear   >/dev/null 2>&1 || true
php artisan route:clear  >/dev/null 2>&1 || true

chown -R www-data:www-data \
    /var/www/pterodactyl/storage \
    /var/www/pterodactyl/bootstrap/cache \
    2>/dev/null || true

chmod -R ug+rwx \
    /var/www/pterodactyl/storage \
    /var/www/pterodactyl/bootstrap/cache \
    2>/dev/null || true

systemctl restart php8.3-fpm 2>/dev/null || \
systemctl restart php8.2-fpm 2>/dev/null || \
systemctl restart php-fpm    2>/dev/null || true

systemctl reload nginx 2>/dev/null || true

ok "Cache Panel bersih, FPM & nginx reload."

# =========================================================
# SAVE RESULT
# =========================================================

cat > "$RESULT_FILE" <<DATA
=========================================================
RAFZHOST PTERODACTYL INSTALLATION
=========================================================

PANEL=https://$PANEL_DOMAIN
NODE=https://$NODE_DOMAIN

EMAIL=$ADMIN_EMAIL
USERNAME=$ADMIN_USERNAME

LOCATION_ID=$LOCATION_ID
NODE_ID=$NODE_ID
NEST_ID=$NEST_ID
EGG_ID=$EGG_ID

ALLOCATION=$PUBLIC_IP:$ALLOCATION_START-$ALLOCATION_END

PLTA=$PLTA
PLTC=$PLTC

=========================================================
DATA

chmod 600 "$RESULT_FILE"

# =========================================================
# CLEAN
# =========================================================

rm -f /tmp/panel-install.sh /tmp/wings-install.sh /tmp/lib.sh
rm -f /tmp/egg.json /tmp/egg_import.json /tmp/rafz_egg.php
rm -f "$WORK_DIR/create_keys.php" "$WORK_DIR/node-config.raw"

# =========================================================
# SUCCESS
# =========================================================

banner "INSTALLASI SELESAI"

echo "Panel       : https://$PANEL_DOMAIN"
echo "Node        : https://$NODE_DOMAIN"
echo "Location ID : $LOCATION_ID"
echo "Node ID     : $NODE_ID"
echo "Nest ID     : $NEST_ID"
echo "Egg ID      : $EGG_ID  ($IMPORT_METHOD)"
echo "Allocation  : $PUBLIC_IP:$ALLOCATION_START-$ALLOCATION_END"
echo
echo "Data        : $RESULT_FILE"
echo "Log         : $LOG_FILE"
echo

ok "Panel + Wings + Location + Node + Allocation + Egg selesai."