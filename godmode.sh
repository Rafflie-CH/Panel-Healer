#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# RAFZHOST - GOD MODE INSTALLER
# Panel + Wings + Location + Node + Allocation + Egg
# Auto-handle: LE rate limit, missing cert, hairpin NAT
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

# ---------- SSL helpers (rate limit safe) ----------
ensure_ssl_cert() {
    local domain="$1"
    local le_live="/etc/letsencrypt/live/${domain}"
    local ssl_dir="/etc/ssl"
    local cert_pem="${ssl_dir}/${domain}.pem"
    local cert_key="${ssl_dir}/${domain}.key"

    mkdir -p "$ssl_dir"

    # 1) pakai LE yang sudah ada
    if [[ -f "${le_live}/fullchain.pem" && -f "${le_live}/privkey.pem" ]]; then
        info "Pakai cert Let's Encrypt yang sudah ada: $domain"
        ln -sfn "${le_live}/fullchain.pem" "$cert_pem"
        ln -sfn "${le_live}/privkey.pem" "$cert_key"
        # perbaiki path di nginx
        find /etc/nginx -type f 2>/dev/null | while read -r f; do
            sed -i \
                -e "s|/etc/ssl/${domain}\\.pem|${le_live}/fullchain.pem|g" \
                -e "s|/etc/ssl/${domain}\\.key|${le_live}/privkey.pem|g" \
                -e "s|ssl_certificate .*${domain}.*pem;|ssl_certificate ${le_live}/fullchain.pem;|g" \
                -e "s|ssl_certificate_key .*${domain}.*key;|ssl_certificate_key ${le_live}/privkey.pem;|g" \
                "$f" 2>/dev/null || true
        done
        return 0
    fi

    # 2) coba certbot non-interactive (abaikan rate limit)
    if command -v certbot >/dev/null 2>&1; then
        info "Coba certbot untuk $domain (non-interactive)..."
        set +e
        certbot certonly --nginx --non-interactive --agree-tos --no-eff-email \
            -m "${ADMIN_EMAIL:-admin@localhost}" -d "$domain" \
            --keep-until-expiring --expand 2>&1 | tail -20
        set -e
        if [[ -f "${le_live}/fullchain.pem" ]]; then
            ok "Certbot OK untuk $domain"
            ln -sfn "${le_live}/fullchain.pem" "$cert_pem"
            ln -sfn "${le_live}/privkey.pem" "$cert_key"
            return 0
        fi
        warn "Certbot gagal / rate limit — fallback self-signed"
    fi

    # 3) self-signed fallback
    if [[ ! -f "$cert_pem" || ! -f "$cert_key" ]]; then
        info "Generate self-signed SSL untuk $domain"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$cert_key" \
            -out "$cert_pem" \
            -subj "/CN=${domain}" >/dev/null 2>&1
    fi

    find /etc/nginx -type f 2>/dev/null | while read -r f; do
        sed -i \
            -e "s|ssl_certificate .*;|ssl_certificate ${cert_pem};|g" \
            -e "s|ssl_certificate_key .*;|ssl_certificate_key ${cert_key};|g" \
            "$f" 2>/dev/null || true
        # only touch files that mention this domain
        if grep -q "$domain" "$f" 2>/dev/null; then
            sed -i \
                -e "s|/etc/ssl/${domain}\\.pem|${cert_pem}|g" \
                -e "s|/etc/ssl/${domain}\\.key|${cert_key}|g" \
                "$f" 2>/dev/null || true
        fi
    done

    ok "SSL siap (self-signed/existing) untuk $domain"
}

fix_nginx_ssl() {
    local domain="$1"
    ensure_ssl_cert "$domain"
    set +e
    nginx -t 2>&1
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        warn "nginx -t masih gagal, coba perbaiki path cert..."
        ensure_ssl_cert "$domain"
        nginx -t || error_exit 1 "nginx config test gagal setelah fix SSL"
    fi
    systemctl reload nginx 2>/dev/null || systemctl restart nginx || true
}

# =========================================================
# ROOT CHECK
# =========================================================

if [[ $EUID -ne 0 ]]; then
    error_exit 1 "Installer wajib dijalankan sebagai root."
fi

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

[[ -n "$PANEL_DOMAIN" ]]    || error_exit 1 "Domain Panel tidak boleh kosong."
[[ -n "$NODE_DOMAIN" ]]     || error_exit 1 "Domain Node tidak boleh kosong."
[[ -n "$ADMIN_EMAIL" ]]     || error_exit 1 "Email Admin tidak boleh kosong."
[[ -n "$ADMIN_USERNAME" ]]  || error_exit 1 "Username Admin tidak boleh kosong."
[[ -n "$ADMIN_PASSWORD" ]]  || error_exit 1 "Password Admin tidak boleh kosong."
[[ "$PANEL_DOMAIN" != "$NODE_DOMAIN" ]] || error_exit 1 "Domain Panel dan Node tidak boleh sama."

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
EGG_NEST_NAME="bot"

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
        echo "OS belum divalidasi: $PRETTY_NAME"
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
    ca-certificates curl wget gnupg jq unzip git \
    redis-server openssl dnsutils lsof python3 \
    || error_exit 1 "Gagal install dependency dasar"

ok "Dependency dasar siap."

# =========================================================
# 03 PUBLIC IP
# =========================================================

run_step "03" "[03] Deteksi IP VPS"

PUBLIC_IP=""
for url in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com" \
    "https://checkip.amazonaws.com"
do
    tmp="$(curl -4fsS --max-time 8 "$url" 2>/dev/null || true)"
    tmp="$(printf '%s' "$tmp" | tr -d '[:space:]')"
    case "$tmp" in
        *[!0-9.]*|'') continue ;;
        *)
            dots="${tmp//[^.]/}"
            if [[ ${#dots} -eq 3 ]]; then
                PUBLIC_IP="$tmp"
                break
            fi
            ;;
    esac
done

if [[ -z "$PUBLIC_IP" ]]; then
    tmp="$(hostname -I 2>/dev/null | tr ' ' '\n' | head -1 || true)"
    tmp="$(printf '%s' "$tmp" | tr -d '[:space:]')"
    case "$tmp" in
        *[!0-9.]*|'') ;;
        *)
            dots="${tmp//[^.]/}"
            [[ ${#dots} -eq 3 ]] && PUBLIC_IP="$tmp"
            ;;
    esac
fi

if [[ -z "$PUBLIC_IP" ]]; then
    tmp="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1 || true)"
    tmp="$(printf '%s' "$tmp" | tr -d '[:space:]')"
    case "$tmp" in
        *[!0-9.]*|'') ;;
        *)
            dots="${tmp//[^.]/}"
            [[ ${#dots} -eq 3 ]] && PUBLIC_IP="$tmp"
            ;;
    esac
fi

if [[ -z "$PUBLIC_IP" ]]; then
    echo
    echo "Gagal deteksi IPv4 otomatis."
    printf "Masukkan IPv4 VPS manual: "
    read -r PUBLIC_IP
    PUBLIC_IP="$(printf '%s' "$PUBLIC_IP" | tr -d '[:space:]')"
fi

case "$PUBLIC_IP" in
    *[!0-9.]*|'') error_exit 1 "IPv4 VPS tidak valid: '$PUBLIC_IP'" ;;
esac
dots="${PUBLIC_IP//[^.]/}"
[[ ${#dots} -eq 3 ]] || error_exit 1 "IPv4 VPS format salah: '$PUBLIC_IP'"

echo "VPS IPv4: $PUBLIC_IP"
ok "IP terdeteksi."

# =========================================================
# 04 DNS
# =========================================================

run_step "04" "[04] Pengecekan DNS"

# pakai DNS publik biar tidak kena /etc/hosts (127.0.0.1 dari run sebelumnya)
PANEL_DNS="$(dig +short A "$PANEL_DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 || true)"
NODE_DNS="$(dig +short A "$NODE_DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 || true)"

# fallback resolver lain
if [[ -z "$PANEL_DNS" ]]; then
    PANEL_DNS="$(dig +short A "$PANEL_DOMAIN" @1.1.1.1 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 || true)"
fi
if [[ -z "$NODE_DNS" ]]; then
    NODE_DNS="$(dig +short A "$NODE_DOMAIN" @1.1.1.1 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 || true)"
fi

echo "Panel DNS (publik) : ${PANEL_DNS:-TIDAK ADA}"
echo "Node DNS  (publik) : ${NODE_DNS:-TIDAK ADA}"
echo "Catatan: entry 127.0.0.1 di /etc/hosts diabaikan (hairpin NAT)."

if [[ "$PANEL_DNS" != "$PUBLIC_IP" ]]; then
    echo "DNS Panel belum ke VPS ($PANEL_DOMAIN => ${PANEL_DNS:-NONE}, VPS $PUBLIC_IP)"
    error_exit 1 "DNS Panel tidak match"
fi
if [[ "$NODE_DNS" != "$PUBLIC_IP" ]]; then
    echo "DNS Node belum ke VPS ($NODE_DOMAIN => ${NODE_DNS:-NONE}, VPS $PUBLIC_IP)"
    error_exit 1 "DNS Node tidak match"
fi

ok "DNS publik terdeteksi dan sesuai IP VPS."

# =========================================================
# 05 PANEL
# =========================================================

run_step "05" "[05] Install Pterodactyl Panel"

# skip full reinstall jika panel sudah ada
if [[ -f /var/www/pterodactyl/artisan ]]; then
    warn "Panel sudah terpasang — skip install, lanjut fix SSL + service"
else
    DB_PASSWORD="$(openssl rand -hex 24)"

    export FQDN="$PANEL_DOMAIN"
    export MYSQL_DB="panel"
    export MYSQL_USER="pterodactyl"
    export MYSQL_PASSWORD="$DB_PASSWORD"
    export timezone="Asia/Jakarta"
    export telemetry="false"
    # jangan paksa LE di installer — kita handle sendiri
    export ASSUME_SSL="true"
    export CONFIGURE_LETSENCRYPT="false"
    export CONFIGURE_FIREWALL="true"
    export email="$ADMIN_EMAIL"
    export user_email="$ADMIN_EMAIL"
    export user_username="$ADMIN_USERNAME"
    export user_firstname="${ADMIN_FIRSTNAME:-Rafz}"
    export user_lastname="${ADMIN_LASTNAME:-Host}"
    export user_password="$ADMIN_PASSWORD"

    info "Mengambil installer resmi $INSTALLER_VERSION..."
    curl -fsSL "$LIB_URL" -o /tmp/lib.sh || error_exit 1 "Gagal download lib.sh"
    curl -fsSL "$PANEL_INSTALLER_URL" -o /tmp/panel-install.sh || error_exit 1 "Gagal download panel installer"
    chmod +x /tmp/panel-install.sh

    # patch biar non-interactive
    sed -i 's/read -r CONFIGURE_SSL/CONFIGURE_SSL=n/g' /tmp/panel-install.sh 2>/dev/null || true
    sed -i 's/^\s*read -r /true #patched /g' /tmp/panel-install.sh 2>/dev/null || true

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
fi

rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# SSL: LE existing / certbot / self-signed — jangan mati karena rate limit
info "Setup SSL Panel (rate-limit safe)..."
ensure_ssl_cert "$PANEL_DOMAIN"

# pastikan APP_URL https
if [[ -f /var/www/pterodactyl/.env ]]; then
    sed -i "s|^APP_URL=.*|APP_URL=https://${PANEL_DOMAIN}|g" /var/www/pterodactyl/.env
fi

cd /var/www/pterodactyl
php artisan optimize:clear >/dev/null 2>&1 || true
chown -R www-data:www-data /var/www/pterodactyl

systemctl enable --now nginx 2>/dev/null || true
systemctl enable --now mariadb 2>/dev/null || true
systemctl enable --now redis-server 2>/dev/null || true
[[ -f /etc/systemd/system/pteroq.service ]] && systemctl enable --now pteroq 2>/dev/null || true

fix_nginx_ssl "$PANEL_DOMAIN"

php artisan --version || error_exit 1 "php artisan gagal"
systemctl is-active --quiet nginx   || error_exit 1 "Nginx tidak aktif"
systemctl is-active --quiet mariadb || error_exit 1 "MariaDB tidak aktif"

ok "Panel terpasang dan service utama aktif."

# =========================================================
# 06 WINGS
# =========================================================

run_step "06" "[06] Install Wings"

if [[ -x /usr/local/bin/wings ]]; then
    warn "Wings binary sudah ada — skip install binary"
else
    export FQDN="$NODE_DOMAIN"
    export EMAIL="$ADMIN_EMAIL"
    export CONFIGURE_FIREWALL="true"
    export CONFIGURE_LETSENCRYPT="false"
    export CONFIGURE_DBHOST="false"

    curl -fsSL "$WINGS_INSTALLER_URL" -o /tmp/wings-install.sh || error_exit 1 "Gagal download wings installer"
    chmod +x /tmp/wings-install.sh
    sed -i 's/^\s*read -r /true #patched /g' /tmp/wings-install.sh 2>/dev/null || true

    # shellcheck source=/dev/null
    source /tmp/lib.sh 2>/dev/null || true

    info "Menjalankan installer Wings..."
    set +e
    bash /tmp/wings-install.sh 2>&1
    WINGS_RC=$?
    set -e

    if [[ $WINGS_RC -ne 0 || ! -x /usr/local/bin/wings ]]; then
        # fallback download binary langsung
        warn "Installer wings gagal, coba download binary..."
        ARCH_W="amd64"
        case "$(uname -m)" in aarch64|arm64) ARCH_W="arm64" ;; esac
        curl -fsSL "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH_W}" \
            -o /usr/local/bin/wings || error_exit 1 "Gagal download wings binary"
        chmod +x /usr/local/bin/wings
    fi
fi

# SSL node domain
ensure_ssl_cert "$NODE_DOMAIN"

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
    out="$(curl -fsS --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 60 "${API_HEADERS[@]}" "$url" 2>&1)"
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
    out="$(curl -fsS --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 60 "${API_HEADERS[@]}" -X POST -d "$data" "$url" 2>&1)"
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

# pastikan hosts biar curl ke panel domain ga hairpin-fail
sed -i "/[[:space:]]$PANEL_DOMAIN[[:space:]]/d" /etc/hosts 2>/dev/null || true
echo "127.0.0.1 $PANEL_DOMAIN" >> /etc/hosts

set +e
LOCATIONS_JSON="$(api_get "$API_BASE/locations?per_page=100")"
LOC_RC=$?
set -e

if [[ $LOC_RC -ne 0 ]]; then
    # coba sekali lagi setelah reload nginx
    systemctl reload nginx 2>/dev/null || true
    sleep 2
    set +e
    LOCATIONS_JSON="$(api_get "$API_BASE/locations?per_page=100")"
    LOC_RC=$?
    set -e
fi

[[ $LOC_RC -eq 0 ]] || error_exit 1 "PLTA tidak bisa mengakses Application API"
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
        echo "API Location gagal:"; api_error "$LOC_CREATE_RAW"
        LOCATIONS_JSON="$(api_get "$API_BASE/locations?per_page=100" 2>/dev/null || true)"
        LOCATION_ID="$(
            printf '%s' "$LOCATIONS_JSON" |
            jq -r --arg short "$LOCATION_SHORT" '
                .data[] | select(.attributes.short == $short) | .attributes.id
            ' | head -1
        )"
        [[ -n "$LOCATION_ID" && "$LOCATION_ID" != "null" ]] || error_exit 1 "Gagal membuat Location"
        ok "Location ternyata sudah dibuat. ID: $LOCATION_ID"
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
        .data[] | select(.attributes.fqdn == $fqdn) | .attributes.id
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
                name: $name, description: $desc, location_id: $location_id,
                fqdn: $fqdn, scheme: "https", behind_proxy: false, public: true,
                daemon_base: "/var/lib/pterodactyl/volumes",
                memory: $memory, memory_overallocate: $mo,
                disk: $disk, disk_overallocate: $do,
                upload_size: $upload, daemon_sftp: $sftp, daemon_listen: $listen,
                maintenance_mode: false
            }'
    )"
    set +e
    NODE_CREATE_RAW="$(api_post "$API_BASE/nodes" "$NODE_BODY" 2>&1)"
    NODE_RC=$?
    set -e
    if [[ $NODE_RC -ne 0 ]]; then
        echo "API Node gagal:"; api_error "$NODE_CREATE_RAW"
        NODES_JSON="$(api_get "$API_BASE/nodes?per_page=100" 2>/dev/null || true)"
        NODE_ID="$(
            printf '%s' "$NODES_JSON" |
            jq -r --arg fqdn "$NODE_DOMAIN" '
                .data[] | select(.attributes.fqdn == $fqdn) | .attributes.id
            ' | head -1
        )"
        [[ -n "$NODE_ID" && "$NODE_ID" != "null" ]] || error_exit 1 "Gagal membuat Node"
        ok "Node ternyata sudah dibuat. ID: $NODE_ID"
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
        echo "API Allocation gagal:"; api_error "$ALLOC_RAW"
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

# pastikan binary ada
if [[ ! -x /usr/local/bin/wings ]]; then
    info "Download wings binary..."
    ARCH_W="amd64"
    case "$(uname -m)" in aarch64|arm64) ARCH_W="arm64" ;; esac
    curl -fsSL "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH_W}" \
        -o /usr/local/bin/wings || error_exit 1 "Gagal download wings binary"
    chmod +x /usr/local/bin/wings
fi

# pastikan Docker terpasang (wajib untuk Wings)
if ! command -v docker >/dev/null 2>&1; then
    info "Docker belum ada — install..."
    set +e
    curl -fsSL https://get.docker.com | sh
    DOCKER_RC=$?
    set -e
    if [[ $DOCKER_RC -ne 0 ]] || ! command -v docker >/dev/null 2>&1; then
        error_exit 1 "Gagal install Docker"
    fi
fi

# enable docker (nama unit bisa docker.service)
systemctl enable --now docker 2>/dev/null || systemctl enable --now docker.socket 2>/dev/null || true
sleep 2
if ! docker info >/dev/null 2>&1; then
    warn "Docker belum siap, coba start ulang..."
    systemctl start docker 2>/dev/null || true
    sleep 3
fi
docker info >/dev/null 2>&1 || error_exit 1 "Docker tidak berjalan"

# buat systemd unit kalau belum ada
if [[ ! -f /etc/systemd/system/wings.service ]]; then
    info "Membuat wings.service..."
    cat > /etc/systemd/system/wings.service << 'WINGSEOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Wants=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
WINGSEOF
else
    # pastikan unit tidak pakai Requires=docker yang bikin gagal total
    sed -i 's/^Requires=docker.service/Wants=docker.service/' /etc/systemd/system/wings.service 2>/dev/null || true
fi

# pastikan config.yml ada
if [[ ! -s /etc/pterodactyl/config.yml ]]; then
    error_exit 1 "config.yml kosong — step 12 gagal?"
fi

systemctl daemon-reload
systemctl enable wings >/dev/null 2>&1 || true
systemctl restart wings || error_exit 1 "Gagal restart wings"
sleep 3

if ! systemctl is-active --quiet wings; then
    echo "===== WINGS LOG ====="
    journalctl -u wings -n 50 --no-pager || true
    error_exit 1 "Wings gagal start"
fi
ok "Wings aktif."

info "Fix /etc/hosts + GUZZLE timeout..."
sed -i "/[[:space:]]$PANEL_DOMAIN[[:space:]]/d" /etc/hosts 2>/dev/null || true
sed -i "/[[:space:]]$NODE_DOMAIN[[:space:]]/d" /etc/hosts 2>/dev/null || true
echo "127.0.0.1 $PANEL_DOMAIN" >> /etc/hosts
echo "127.0.0.1 $NODE_DOMAIN" >> /etc/hosts

if [[ -f /var/www/pterodactyl/.env ]]; then
    sed -i '/^GUZZLE_TIMEOUT=/d' /var/www/pterodactyl/.env
    sed -i '/^GUZZLE_CONNECT_TIMEOUT=/d' /var/www/pterodactyl/.env
    echo 'GUZZLE_TIMEOUT=900' >> /var/www/pterodactyl/.env
    echo 'GUZZLE_CONNECT_TIMEOUT=60' >> /var/www/pterodactyl/.env
fi

systemctl restart wings 2>/dev/null || true
sleep 2
ok "Hosts + Guzzle di-refresh."

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
# 15 IMPORT EGG
# =========================================================

run_step "15" "[15] Import Egg — Nusantara Project GOD MODE"

info "Menulis egg.json..."
EGG_B64="eyJfY29tbWVudCI6ICJETyBOT1QgRURJVCIsICJtZXRhIjogeyJ2ZXJzaW9uIjogIlBURExfdjIiLCAidXBkYXRlX3VybCI6IG51bGx9LCAiZXhwb3J0ZWRfYXQiOiAiMjAyNi0wOC0yNFQwNjozNDowNiswNzowMCIsICJuYW1lIjogIk51c2FudGFyYSBQcm9qZWN0IC0gVUxUSU1BVEUgR09EIE1PREUgKFVuaWZpZWQpIiwgImF1dGhvciI6ICJyYWZ6aG9zdEByYWZ6aG9zdC5teS5pZCIsICJkZXNjcmlwdGlvbiI6ICJTYXR1IEVnZyB1bnR1ayBtZW5ndWFzYWkgc2VtdWFueWEuIEJpc2Egc3dpdGNoIGFudGFyYSBZQVJOIC8gTlBNIGxhbmdzdW5nIGRhcmkgcGFuZWwuIiwgImZlYXR1cmVzIjogW10sICJkb2NrZXJfaW1hZ2VzIjogeyJOb2RlSlMgMjQiOiAiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzI0IiwgIk5vZGVKUyAyMyI6ICJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjMiLCAiTm9kZUpTIDIyIjogImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOm5vZGVqc18yMiIsICJOb2RlSlMgMjEiOiAiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzIxIiwgIk5vZGVKUyAyMCI6ICJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjAiLCAiTm9kZUpTIDE5IjogImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOm5vZGVqc18xOSIsICJOb2RlSlMgMTgiOiAiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzE4IiwgIk5vZGVKUyAxNyI6ICJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTciLCAiTm9kZUpTIDE2IjogImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOm5vZGVqc18xNiIsICJOb2RlSlMgMTUiOiAiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzE1IiwgIlB5dGhvbiAzLjEyIjogImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnB5dGhvbl8zLjEyIiwgIlB5dGhvbiAzLjExIjogImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnB5dGhvbl8zLjExIiwgIlB5dGhvbiAzLjEwIjogImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnB5dGhvbl8zLjEwIiwgIlB5dGhvbiAzLjkiOiAiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6cHl0aG9uXzMuOSIsICJQeXRob24gMy44IjogImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnB5dGhvbl8zLjgiLCAiRGViaWFuIE9TIChVbml2ZXJzYWwpIjogImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOmRlYmlhbiIsICJVYnVudHUgT1MgKFVuaXZlcnNhbCkiOiAiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6dWJ1bnR1In0sICJmaWxlX2RlbnlsaXN0IjogW10sICJzdGFydHVwIjogImlmIFtbIC1kIC5naXQgXV0gJiYgW1sgXCJ7e0FVVE9fVVBEQVRFfX1cIiA9PSBcIjFcIiBdXTsgdGhlbiBnaXQgcHVsbDsgZmk7IGlmIFtbICEgLXogJHtDTE9VREZMQVJFRF9UT0tFTn0gXV07IHRoZW4gZWNobyBcIk1lbXVsYWkgQ2xvdWRmbGFyZWQgVHVubmVsLi4uXCI7IHdnZXQgLXEgaHR0cHM6Ly9naXRodWIuY29tL2Nsb3VkZmxhcmUvY2xvdWRmbGFyZWQvcmVsZWFzZXMvbGF0ZXN0L2Rvd25sb2FkL2Nsb3VkZmxhcmVkLWxpbnV4LWFtZDY0IC1PIGNsb3VkZmxhcmVkICYmIGNobW9kICt4IGNsb3VkZmxhcmVkICYmIC4vY2xvdWRmbGFyZWQgdHVubmVsIC0tbm8tYXV0b3VwZGF0ZSBydW4gLS10b2tlbiAke0NMT1VERkxBUkVEX1RPS0VOfSA+IC9kZXYvbnVsbCAyPiYxICYgZmk7IHJlcV9maWxlPSR7UkVRVUlSRU1FTlRTX0ZJTEU6LXJlcXVpcmVtZW50cy50eHR9OyBpZiBbIC1mIC9ob21lL2NvbnRhaW5lci8kcmVxX2ZpbGUgXTsgdGhlbiBwaXAgaW5zdGFsbCAtciAkcmVxX2ZpbGU7IGZpOyBpZiBbIFwiJHtQQUNLQUdFX01BTkFHRVJ9XCIgPT0gXCJucG1cIiBdOyB0aGVuIGlmIFtbICEgLXogJHtOT0RFX1BBQ0tBR0VTfSBdXTsgdGhlbiB5ZXMgXCJcIiB8IG5wbSBpbnN0YWxsICR7Tk9ERV9QQUNLQUdFU30gLS1sZWdhY3ktcGVlci1kZXBzIC0tbm8tZnVuZCAtLW5vLWF1ZGl0OyBmaTsgaWYgW1sgISAteiAke1VOTk9ERV9QQUNLQUdFU30gXV07IHRoZW4geWVzIFwiXCIgfCBucG0gdW5pbnN0YWxsICR7VU5OT0RFX1BBQ0tBR0VTfSAtLW5vLWZ1bmQgLS1uby1hdWRpdDsgZmk7IGlmIFsgLWYgL2hvbWUvY29udGFpbmVyL3BhY2thZ2UuanNvbiBdOyB0aGVuIHllcyBcIlwiIHwgbnBtIGluc3RhbGwgLS1sZWdhY3ktcGVlci1kZXBzIC0tbm8tZnVuZCAtLW5vLWF1ZGl0OyBmaTsgcm0gLXJmIC5ucG0gLmxvZyAuY2FjaGUgLS1mb3JjZTsgZWxzZSBpZiBbWyAhIC16ICR7Tk9ERV9QQUNLQUdFU30gXV07IHRoZW4geWVzIHwgeWFybiBhZGQgJHtOT0RFX1BBQ0tBR0VTfSAtLW5vbi1pbnRlcmFjdGl2ZSAtLWlnbm9yZS1lbmdpbmVzOyBmaTsgaWYgW1sgISAteiAke1VOTk9ERV9QQUNLQUdFU30gXV07IHRoZW4geWVzIHwgeWFybiByZW1vdmUgJHtVTk5PREVfUEFDS0FHRVN9IC0tbm9uLWludGVyYWN0aXZlOyBmaTsgaWYgWyAtZiAvaG9tZS9jb250YWluZXIvcGFja2FnZS5qc29uIF07IHRoZW4geWVzIHwgeWFybiBpbnN0YWxsIC0tbm9uLWludGVyYWN0aXZlIC0taWdub3JlLWVuZ2luZXM7IGZpOyBybSAtcmYgLm5wbSAubG9nIC5jYWNoZSAueWFybi1jYWNoZSAtLWZvcmNlOyBmaTsgaWYgW1sgISAteiAke0NVU1RPTV9FTlZJUk9OTUVOVF9WQVJJQUJMRVN9IF1dOyB0aGVuIHZhcnM9JChlY2hvICR7Q1VTVE9NX0VOVklST05NRU5UX1ZBUklBQkxFU30gfCB0ciBcIjtcIiBcIlxcblwiKTsgZm9yIGxpbmUgaW4gJHZhcnM7IGRvIGV4cG9ydCAkbGluZTsgZG9uZSBmaTsgZXZhbCAke0NNRF9SVU59OyIsICJjb25maWciOiB7ImZpbGVzIjogInt9IiwgInN0YXJ0dXAiOiAie1xyXG4gICAgXCJkb25lXCI6IFwicnVubmluZ1wiXHJcbn0iLCAibG9ncyI6ICJ7fSIsICJzdG9wIjogIl5eQyJ9LCAic2NyaXB0cyI6IHsiaW5zdGFsbGF0aW9uIjogeyJzY3JpcHQiOiAiIyEvYmluL2Jhc2hcbmFwdCB1cGRhdGVcbmFwdCBpbnN0YWxsIC15IGdpdCBjdXJsIHdnZXQganEgZmlsZSB1bnppcCBtYWtlIGdjYyBnKysgcHl0aG9uMyBweXRob24zLWRldiBweXRob24zLXBpcCBsaWJ0b29sXG5pZiBjb21tYW5kIC12IG5wbSAmPiAvZGV2L251bGw7IHRoZW4gbnBtIGluc3RhbGwgLWcgeWFybjsgZmlcbm1rZGlyIC1wIC9tbnQvc2VydmVyXG5jZCAvbW50L3NlcnZlclxuaWYgWyBcIiR7VVNFUl9VUExPQUR9XCIgPT0gXCJ0cnVlXCIgXSB8fCBbIFwiJHtVU0VSX1VQTE9BRH1cIiA9PSBcIjFcIiBdOyB0aGVuIGVjaG8gZG9uZTsgZXhpdCAwOyBmaVxuaWYgW1sgJHtHSVRfQUREUkVTU30gIT0gKi5naXQgXV07IHRoZW4gR0lUX0FERFJFU1M9JHtHSVRfQUREUkVTU30uZ2l0OyBmaVxuaWYgWyAteiBcIiR7VVNFUk5BTUV9XCIgXSAmJiBbIC16IFwiJHtBQ0NFU1NfVE9LRU59XCIgXTsgdGhlbiBlY2hvIGFub247IGVsc2UgR0lUX0FERFJFU1M9XCJodHRwczovLyR7VVNFUk5BTUV9OiR7QUNDRVNTX1RPS0VOfUAkKGVjaG8gLWUgJHtHSVRfQUREUkVTU30gfCBjdXQgLWQvIC1mMy0pXCI7IGZpXG5pZiBbIFwiJChscyAtQSAvbW50L3NlcnZlcilcIiBdOyB0aGVuIGlmIFsgLWQgLmdpdCBdICYmIFsgLWYgLmdpdC9jb25maWcgXTsgdGhlbiBPUklHSU49JChnaXQgY29uZmlnIC0tZ2V0IHJlbW90ZS5vcmlnaW4udXJsKTsgaWYgWyBcIiR7T1JJR0lOfVwiID09IFwiJHtHSVRfQUREUkVTU31cIiBdOyB0aGVuIGdpdCBwdWxsOyBmaTsgZmk7IGVsc2UgaWYgWyAteiAke0JSQU5DSH0gXTsgdGhlbiBnaXQgY2xvbmUgJHtHSVRfQUREUkVTU30gLjsgZWxzZSBnaXQgY2xvbmUgLS1zaW5nbGUtYnJhbmNoIC0tYnJhbmNoICR7QlJBTkNIfSAke0dJVF9BRERSRVNTfSAuOyBmaTsgZmlcbmlmIFsgLWYgL21udC9zZXJ2ZXIvcGFja2FnZS5qc29uIF07IHRoZW4gaWYgWyBcIiR7UEFDS0FHRV9NQU5BR0VSfVwiID09IFwibnBtXCIgXTsgdGhlbiBybSAtcmYgbm9kZV9tb2R1bGVzIHBhY2thZ2UtbG9jay5qc29uOyB5ZXMgXCJcIiB8IG5wbSBpbnN0YWxsIC0tcHJvZHVjdGlvbiAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXQ7IGVsc2Ugcm0gLWYgcGFja2FnZS1sb2NrLmpzb247IHllcyB8IHlhcm4gaW5zdGFsbCAtLXByb2R1Y3Rpb24gLS1ub24taW50ZXJhY3RpdmUgLS1pZ25vcmUtZW5naW5lczsgZmk7IGZpXG5yZXFfZmlsZT0ke1JFUVVJUkVNRU5UU19GSUxFOi1yZXF1aXJlbWVudHMudHh0fVxuaWYgWyAtZiAvbW50L3NlcnZlci8kcmVxX2ZpbGUgXTsgdGhlbiBwaXAgaW5zdGFsbCAtciAkcmVxX2ZpbGU7IGZpXG5lY2hvIGluc3RhbGwgY29tcGxldGVcbmV4aXQgMCIsICJjb250YWluZXIiOiAiZGViaWFuOmJ1bGxzZXllLXNsaW0iLCAiZW50cnlwb2ludCI6ICJiYXNoIn19LCAidmFyaWFibGVzIjogW3sibmFtZSI6ICJHVU5BS0FOIEZJTEUgVVBMT0FEIE1BTlVBTD8iLCAiZGVzY3JpcHRpb24iOiAiVXBsb2FkIG1hbnVhbCAoMSkgYXRhdSBnaXQgY2xvbmUgKDApLiBSZWluc3RhbGwgU2VydmVyIHVudHVrIGFwcGx5IGdpdC4iLCAiZW52X3ZhcmlhYmxlIjogIlVTRVJfVVBMT0FEIiwgImRlZmF1bHRfdmFsdWUiOiAiMSIsICJ1c2VyX3ZpZXdhYmxlIjogdHJ1ZSwgInVzZXJfZWRpdGFibGUiOiB0cnVlLCAicnVsZXMiOiAibnVsbGFibGV8Ym9vbGVhbiIsICJmaWVsZF90eXBlIjogInRleHQifSwgeyJuYW1lIjogIlBBQ0tBR0UgTUFOQUdFUiAoWUFSTiAvIE5QTSkiLCAiZGVzY3JpcHRpb24iOiAieWFybiBhdGF1IG5wbSIsICJlbnZfdmFyaWFibGUiOiAiUEFDS0FHRV9NQU5BR0VSIiwgImRlZmF1bHRfdmFsdWUiOiAieWFybiIsICJ1c2VyX3ZpZXdhYmxlIjogdHJ1ZSwgInVzZXJfZWRpdGFibGUiOiB0cnVlLCAicnVsZXMiOiAibnVsbGFibGV8c3RyaW5nfGluOnlhcm4sbnBtIiwgImZpZWxkX3R5cGUiOiAidGV4dCJ9LCB7Im5hbWUiOiAiRklMRSBVVEFNQSBTQ1JJUFQgKEVOVFJZIEZJTEUpIiwgImRlc2NyaXB0aW9uIjogIkNvbnRvaDogeWFybiBzdGFydCwgbnBtIHN0YXJ0LCBweXRob24gbWFpbi5weSIsICJlbnZfdmFyaWFibGUiOiAiQ01EX1JVTiIsICJkZWZhdWx0X3ZhbHVlIjogInlhcm4gc3RhcnQiLCAidXNlcl92aWV3YWJsZSI6IHRydWUsICJ1c2VyX2VkaXRhYmxlIjogdHJ1ZSwgInJ1bGVzIjogInJlcXVpcmVkfHN0cmluZyIsICJmaWVsZF90eXBlIjogInRleHQifSwgeyJuYW1lIjogIkZJTEUgTElCUkFSWSAvIFJFUVVJUkVNRU5UUyIsICJkZXNjcmlwdGlvbiI6ICJyZXF1aXJlbWVudHMudHh0IiwgImVudl92YXJpYWJsZSI6ICJSRVFVSVJFTUVOVFNfRklMRSIsICJkZWZhdWx0X3ZhbHVlIjogInJlcXVpcmVtZW50cy50eHQiLCAidXNlcl92aWV3YWJsZSI6IHRydWUsICJ1c2VyX2VkaXRhYmxlIjogdHJ1ZSwgInJ1bGVzIjogIm51bGxhYmxlfHN0cmluZyIsICJmaWVsZF90eXBlIjogInRleHQifSwgeyJuYW1lIjogIkxJTksgUkVQT1NJVE9SSSBHSVQgKE9QU0lPTkFMKSIsICJkZXNjcmlwdGlvbiI6ICJVUkwgZ2l0aHViIHJlcG8uIFdhamliIFJlaW5zdGFsbCBTZXJ2ZXIuIiwgImVudl92YXJpYWJsZSI6ICJHSVRfQUREUkVTUyIsICJkZWZhdWx0X3ZhbHVlIjogIiIsICJ1c2VyX3ZpZXdhYmxlIjogdHJ1ZSwgInVzZXJfZWRpdGFibGUiOiB0cnVlLCAicnVsZXMiOiAibnVsbGFibGV8c3RyaW5nIiwgImZpZWxkX3R5cGUiOiAidGV4dCJ9LCB7Im5hbWUiOiAiSW5zdGFsbCBCcmFuY2giLCAiZGVzY3JpcHRpb24iOiAiQnJhbmNoIGdpdCIsICJlbnZfdmFyaWFibGUiOiAiQlJBTkNIIiwgImRlZmF1bHRfdmFsdWUiOiAiIiwgInVzZXJfdmlld2FibGUiOiB0cnVlLCAidXNlcl9lZGl0YWJsZSI6IHRydWUsICJydWxlcyI6ICJudWxsYWJsZXxzdHJpbmciLCAiZmllbGRfdHlwZSI6ICJ0ZXh0In0sIHsibmFtZSI6ICJBdXRvIFVwZGF0ZSIsICJkZXNjcmlwdGlvbiI6ICIxPXB1bGwgb24gc3RhcnQiLCAiZW52X3ZhcmlhYmxlIjogIkFVVE9fVVBEQVRFIiwgImRlZmF1bHRfdmFsdWUiOiAiMSIsICJ1c2VyX3ZpZXdhYmxlIjogdHJ1ZSwgInVzZXJfZWRpdGFibGUiOiB0cnVlLCAicnVsZXMiOiAibnVsbGFibGV8Ym9vbGVhbiIsICJmaWVsZF90eXBlIjogInRleHQifSwgeyJuYW1lIjogIkNsb3VkZmxhcmVkIFRva2VuIiwgImRlc2NyaXB0aW9uIjogIlRva2VuIGNsb3VkZmxhcmUgdHVubmVsIiwgImVudl92YXJpYWJsZSI6ICJDTE9VREZMQVJFRF9UT0tFTiIsICJkZWZhdWx0X3ZhbHVlIjogIiIsICJ1c2VyX3ZpZXdhYmxlIjogdHJ1ZSwgInVzZXJfZWRpdGFibGUiOiB0cnVlLCAicnVsZXMiOiAibnVsbGFibGV8c3RyaW5nIiwgImZpZWxkX3R5cGUiOiAidGV4dCJ9LCB7Im5hbWUiOiAiR2l0IFVzZXJuYW1lIiwgImRlc2NyaXB0aW9uIjogIkdpdCB1c2VyIiwgImVudl92YXJpYWJsZSI6ICJVU0VSTkFNRSIsICJkZWZhdWx0X3ZhbHVlIjogIiIsICJ1c2VyX3ZpZXdhYmxlIjogdHJ1ZSwgInVzZXJfZWRpdGFibGUiOiB0cnVlLCAicnVsZXMiOiAibnVsbGFibGV8c3RyaW5nIiwgImZpZWxkX3R5cGUiOiAidGV4dCJ9LCB7Im5hbWUiOiAiR2l0IEFjY2VzcyBUb2tlbiIsICJkZXNjcmlwdGlvbiI6ICJHaXQgdG9rZW4iLCAiZW52X3ZhcmlhYmxlIjogIkFDQ0VTU19UT0tFTiIsICJkZWZhdWx0X3ZhbHVlIjogIiIsICJ1c2VyX3ZpZXdhYmxlIjogdHJ1ZSwgInVzZXJfZWRpdGFibGUiOiB0cnVlLCAicnVsZXMiOiAibnVsbGFibGV8c3RyaW5nIiwgImZpZWxkX3R5cGUiOiAidGV4dCJ9XX0="
printf '%s' "$EGG_B64" | base64 -d > /tmp/egg.json

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
if (!$eggData) { echo "EGG_JSON_ERROR\n"; exit(1); }

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

\Pterodactyl\Models\Egg::where("nest_id", $nestId)
    ->where("name", $eggData["name"] ?? "")
    ->delete();

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
    echo "Egg import gagal:"; echo "$EGG_OUTPUT"
    error_exit 1 "Egg import gagal"
fi
ok "Egg berhasil diimport. ID: $EGG_ID  Nest ID: $NEST_ID  Metode: $IMPORT_METHOD"

info "Membersihkan cache Panel..."
cd /var/www/pterodactyl
php artisan config:clear >/dev/null 2>&1 || true
php artisan cache:clear  >/dev/null 2>&1 || true
php artisan view:clear   >/dev/null 2>&1 || true
php artisan route:clear  >/dev/null 2>&1 || true
chown -R www-data:www-data /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache 2>/dev/null || true
chmod -R ug+rwx /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache 2>/dev/null || true
systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php8.2-fpm 2>/dev/null || systemctl restart php-fpm 2>/dev/null || true
systemctl reload nginx 2>/dev/null || true
ok "Cache Panel bersih."

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

rm -f /tmp/panel-install.sh /tmp/wings-install.sh /tmp/lib.sh
rm -f /tmp/egg.json /tmp/egg_import.json /tmp/rafz_egg.php
rm -f "$WORK_DIR/create_keys.php" "$WORK_DIR/node-config.raw"

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
