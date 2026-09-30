#!/usr/bin/env bash
set -Eeuo pipefail

# =========================================================
# RAFZHOST - GOD MODE INSTALLER
# Panel + Wings + Location + Node + Allocation + Egg
# Auto-handle: LE rate limit, missing cert, hairpin NAT
# v2.2: + custom alloc IP/alias, behind_proxy, node-domain fix
#       token self-heal, reverse-proxy 443, no /etc/hosts 127.0.0.1
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

    if [[ -f "${le_live}/fullchain.pem" && -f "${le_live}/privkey.pem" ]]; then
        info "Pakai cert Let's Encrypt yang sudah ada: $domain"
        ln -sfn "${le_live}/fullchain.pem" "$cert_pem"
        ln -sfn "${le_live}/privkey.pem" "$cert_key"
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
# HEADER + DETECT + INPUT
# =========================================================

banner "RAFZHOST x DEKZYMARKET - GOD MODE INSTALLER"

PANEL_INSTALLED=0
FORCE_REINSTALL=0
WINGS_BINARY=0
WINGS_CONFIG=0
WINGS_SERVICE=0
WINGS_INSTALLED=0
DOCKER_INSTALLED=0

[[ -f /var/www/pterodactyl/artisan ]] && PANEL_INSTALLED=1
[[ -x /usr/local/bin/wings ]] && WINGS_BINARY=1
[[ -s /etc/pterodactyl/config.yml ]] && WINGS_CONFIG=1
systemctl is-enabled wings >/dev/null 2>&1 && WINGS_SERVICE=1 || true
systemctl is-active --quiet wings 2>/dev/null && WINGS_SERVICE=1 || true
if [[ $WINGS_BINARY -eq 1 && $WINGS_CONFIG -eq 1 ]]; then
    WINGS_INSTALLED=1
fi
command -v docker >/dev/null 2>&1 && DOCKER_INSTALLED=1

PANEL_DOMAIN=""
NODE_DOMAIN=""
ADMIN_EMAIL=""
ADMIN_USERNAME=""
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="Rafz"
ADMIN_PASSWORD=""
PLTA=""
PLTC=""

if [[ -f "$RESULT_FILE" ]]; then
    info "Data install sebelumnya: $RESULT_FILE"
    while IFS='=' read -r k v; do
        case "$k" in
            PANEL) PANEL_DOMAIN="${v#https://}"; PANEL_DOMAIN="${PANEL_DOMAIN%%/*}" ;;
            NODE) NODE_DOMAIN="${v#https://}"; NODE_DOMAIN="${NODE_DOMAIN%%/*}" ;;
            EMAIL) ADMIN_EMAIL="$v" ;;
            USERNAME) ADMIN_USERNAME="$v" ;;
            PASSWORD) ADMIN_PASSWORD="$v" ;;
            FIRSTNAME) ADMIN_FIRSTNAME="$v" ;;
            LASTNAME) ADMIN_LASTNAME="$v" ;;
            PLTA) PLTA="$v" ;;
            PLTC) PLTC="$v" ;;
        esac
    done < <(grep -E '^(PANEL|NODE|EMAIL|USERNAME|PASSWORD|FIRSTNAME|LASTNAME|PLTA|PLTC)=' "$RESULT_FILE" 2>/dev/null || true)
fi

if [[ $PANEL_INSTALLED -eq 0 ]]; then
    PANEL_DOMAIN=""
    NODE_DOMAIN=""
fi

if [[ -z "$PANEL_DOMAIN" && -f /var/www/pterodactyl/.env ]]; then
    PANEL_DOMAIN="$(grep -E '^APP_URL=' /var/www/pterodactyl/.env 2>/dev/null | head -1 | cut -d= -f2- | sed 's|https\?://||;s|/.*||' | tr -d '"' | tr -d "'")"
fi

# Node domain: JANGAN dari field remote: (itu URL panel). Hanya result file / input user.
if [[ $PANEL_INSTALLED -eq 0 ]]; then
    NODE_DOMAIN=""
fi

echo
echo "----- STATUS SISTEM -----"
echo "Panel  : $([ $PANEL_INSTALLED -eq 1 ] && echo 'SUDAH TERPASANG' || echo 'BELUM')"
if [[ $WINGS_INSTALLED -eq 1 ]]; then
    echo "Wings  : SUDAH TERPASANG (binary+config)"
elif [[ $WINGS_BINARY -eq 1 ]]; then
    echo "Wings  : SISA BINARY (belum lengkap — akan di-setup ulang)"
else
    echo "Wings  : BELUM"
fi
echo "Docker : $([ $DOCKER_INSTALLED -eq 1 ] && echo 'SUDAH TERPASANG' || echo 'BELUM')"
if [[ -n "$PANEL_DOMAIN" ]]; then echo "Domain panel terdeteksi : $PANEL_DOMAIN"; fi
if [[ -n "$NODE_DOMAIN" && $PANEL_INSTALLED -eq 1 ]]; then
    echo "Domain node terdeteksi  : $NODE_DOMAIN"
elif [[ -n "$NODE_DOMAIN" && $PANEL_INSTALLED -eq 0 ]]; then
    echo "Domain node (sisa lama) : $NODE_DOMAIN  [diabaikan untuk install baru]"
    NODE_DOMAIN=""
fi
echo "-------------------------"
echo

# Panel/Wings "sudah ada" sering corrupt (SSL/LE/partial) — tawarkan force reinstall
FORCE_REINSTALL=0
if [[ $PANEL_INSTALLED -eq 1 || $WINGS_INSTALLED -eq 1 || $WINGS_BINARY -eq 1 ]]; then
    warn "Ada sisa install sebelumnya (bisa corrupt)."
    printf "Force reinstall dari nol? (y/N): "
    read -r _fr
    case "${_fr,,}" in
        y|yes|ya)
            FORCE_REINSTALL=1
            warn "FORCE REINSTALL aktif — anggap belum terpasang."
            PANEL_INSTALLED=0
            WINGS_INSTALLED=0
            WINGS_CONFIG=0
            # jangan hapus binary wings (download mahal); config & panel path di-handle step 05/06
            rm -f /etc/pterodactyl/config.yml 2>/dev/null || true
            # bersihkan nginx node vhost lama
            rm -f /etc/nginx/sites-enabled/pterodactyl-node.conf 2>/dev/null || true
            rm -f /etc/nginx/sites-available/pterodactyl-node.conf 2>/dev/null || true
            # optional: kosongkan domain dari result lama biar input ulang
            PANEL_DOMAIN=""
            NODE_DOMAIN=""
            PLTA=""
            PLTC=""
            ok "Mode INSTALL BARU (force)."
            ;;
        *)
            info "Lanjut RESUME / perbaiki yang ada."
            ;;
    esac
    echo
fi

if [[ $PANEL_INSTALLED -eq 0 && $WINGS_BINARY -eq 1 ]]; then
    warn "Ketemu sisa wings dari install sebelumnya (panel sudah hilang)."
    info "Binary wings akan dipakai ulang; config lama diabaikan."
    rm -f /etc/pterodactyl/config.yml 2>/dev/null || true
    WINGS_CONFIG=0
    WINGS_INSTALLED=0
fi

ask() {
    local __var="$1" __prompt="$2" __def="${3:-}" __secret="${4:-0}" __val=""
    if [[ -n "$__def" ]]; then
        if [[ "$__secret" == "1" ]]; then
            printf "%s [tersimpan]: " "$__prompt"
        else
            printf "%s [%s]: " "$__prompt" "$__def"
        fi
    else
        printf "%s: " "$__prompt"
    fi
    if [[ "$__secret" == "1" ]]; then
        read -rs __val
        echo
    else
        read -r __val
    fi
    [[ -z "$__val" ]] && __val="$__def"
    printf -v "$__var" '%s' "$__val"
}

if [[ $PANEL_INSTALLED -eq 1 ]]; then
    info "Mode RESUME — tekan Enter untuk pakai nilai terdeteksi."
    ask PANEL_DOMAIN "Domain Panel" "$PANEL_DOMAIN"
    ask NODE_DOMAIN "Domain Node" "$NODE_DOMAIN"
    if [[ -z "$ADMIN_EMAIL" ]]; then
        ask ADMIN_EMAIL "Email Admin"
    fi
    if [[ -z "$ADMIN_USERNAME" ]]; then
        ask ADMIN_USERNAME "Username Admin" "admin"
    fi
    if [[ -z "$ADMIN_PASSWORD" || "$ADMIN_PASSWORD" == "(sudah"* ]]; then
        info "Password admin: pakai yang di $RESULT_FILE (tidak diminta ulang)"
        [[ -z "$ADMIN_PASSWORD" ]] && ADMIN_PASSWORD="(lihat $RESULT_FILE)"
    fi
    [[ -z "$ADMIN_EMAIL" ]] && ADMIN_EMAIL="admin@gmail.com"
    [[ -z "$ADMIN_USERNAME" ]] && ADMIN_USERNAME="admin"
else
    info "Mode INSTALL BARU — isi semua data."
    ask PANEL_DOMAIN "Domain Panel" "$PANEL_DOMAIN"
    ask NODE_DOMAIN "Domain Node" "$NODE_DOMAIN"
    ask ADMIN_EMAIL "Email Admin" "${ADMIN_EMAIL:-}"
    ask ADMIN_USERNAME "Username Admin" "${ADMIN_USERNAME:-admin}"
    ask ADMIN_FIRSTNAME "Nama Depan" "${ADMIN_FIRSTNAME:-Admin}"
    ask ADMIN_LASTNAME "Nama Belakang" "${ADMIN_LASTNAME:-Rafz}"
    ask ADMIN_PASSWORD "Password Admin" "${ADMIN_PASSWORD:-}" 1
fi

[[ -n "$PANEL_DOMAIN" ]]    || error_exit 1 "Domain Panel tidak boleh kosong."
[[ -n "$NODE_DOMAIN" ]]     || error_exit 1 "Domain Node tidak boleh kosong."
[[ -n "$ADMIN_EMAIL" ]]     || error_exit 1 "Email Admin tidak boleh kosong."
[[ -n "$ADMIN_USERNAME" ]]  || error_exit 1 "Username Admin tidak boleh kosong."
if [[ $PANEL_INSTALLED -eq 0 ]]; then
    [[ -n "$ADMIN_PASSWORD" ]] || error_exit 1 "Password Admin tidak boleh kosong."
fi
[[ "$PANEL_DOMAIN" != "$NODE_DOMAIN" ]] || error_exit 1 "Domain Panel dan Node tidak boleh sama."

ALLOC_IP=""
ALLOC_ALIAS=""
ask ALLOC_IP "IP Allocation (Enter = auto IP VPS)" "${ALLOC_IP:-}"
ask ALLOC_ALIAS "Alias Allocation (Enter = nama node)" "${ALLOC_ALIAS:-}"

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
info "Mode      : $([ "$PANEL_INSTALLED" -eq 1 ] && echo 'RESUME / FIX' || echo 'INSTALL BARU')"
info "Panel     : $PANEL_DOMAIN"
info "Node      : $NODE_DOMAIN"
info "Admin     : $ADMIN_USERNAME <$ADMIN_EMAIL>"
info "Location  : $LOCATION_SHORT"
info "Ports     : $ALLOCATION_START-$ALLOCATION_END"
info "Nest      : $EGG_NEST_NAME"
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

[[ -z "$ALLOC_IP" ]] && ALLOC_IP="$PUBLIC_IP"
[[ -z "$ALLOC_ALIAS" ]] && ALLOC_ALIAS="$NODE_NAME"
echo "Alloc IP : $ALLOC_IP"
echo "Alias    : $ALLOC_ALIAS"

# =========================================================
# 04 DNS
# =========================================================

run_step "04" "[04] Pengecekan DNS"

PANEL_DNS="$(dig +short A "$PANEL_DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 || true)"
NODE_DNS="$(dig +short A "$NODE_DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -1 || true)"

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

sed -i "/[[:space:]]$PANEL_DOMAIN[[:space:]]/d" /etc/hosts 2>/dev/null || true
sed -i "/[[:space:]]$NODE_DOMAIN[[:space:]]/d" /etc/hosts 2>/dev/null || true
sed -i "/[[:space:]]$PANEL_DOMAIN[[:space:]]/d; /[[:space:]]$NODE_DOMAIN[[:space:]]/d" \
    /etc/cloud/templates/hosts.debian.tmpl 2>/dev/null || true
ok "Sisa /etc/hosts 127.0.0.1 (jika ada) dibersihkan."
# =========================================================
# 05 PANEL
# =========================================================

run_step "05" "[05] Install Pterodactyl Panel"

if [[ "${FORCE_REINSTALL:-0}" -eq 1 && -f /var/www/pterodactyl/artisan ]]; then
    warn "FORCE REINSTALL — bersihkan panel lama..."
    systemctl stop pteroq 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    # jangan drop DB otomatis total biar aman; installer official handle recreate
    # hapus app files supaya installer jalan penuh
    rm -rf /var/www/pterodactyl
    ok "Panel files dihapus, lanjut install fresh."
fi

if [[ -f /var/www/pterodactyl/artisan && "${FORCE_REINSTALL:-0}" -eq 0 ]]; then
    warn "Panel sudah terpasang — skip install, lanjut fix SSL + service"
else
    DB_PASSWORD="$(openssl rand -hex 24)"

    export FQDN="$PANEL_DOMAIN"
    export MYSQL_DB="panel"
    export MYSQL_USER="pterodactyl"
    export MYSQL_PASSWORD="$DB_PASSWORD"
    export timezone="Asia/Jakarta"
    export telemetry="false"
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

info "Setup SSL Panel (rate-limit safe)..."
ensure_ssl_cert "$PANEL_DOMAIN"

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

if ! command -v docker >/dev/null 2>&1; then
    info "Install Docker..."
    set +e
    curl -fsSL https://get.docker.com | sh
    set -e
fi

systemctl enable docker.socket 2>/dev/null || true
systemctl start docker.socket 2>/dev/null || true
systemctl enable docker 2>/dev/null || true
set +e
systemctl start docker 2>/dev/null
set -e

if ! docker info >/dev/null 2>&1; then
    warn "Docker belum jalan — coba fallback iptables legacy..."
    set +e
    apt-get install -y -qq iptables 2>/dev/null
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null
    systemctl reset-failed docker 2>/dev/null
    systemctl restart docker 2>/dev/null
    sleep 2
    set -e
fi

if docker info >/dev/null 2>&1; then
    ok "Docker aktif."
else
    warn "Docker masih bermasalah — lanjut install wings binary dulu, start di step 13."
fi

if [[ -x /usr/local/bin/wings ]]; then
    warn "Wings binary sudah ada — skip download"
else
    info "Download wings binary..."
    ARCH_W="amd64"
    case "$(uname -m)" in aarch64|arm64) ARCH_W="arm64" ;; esac
    set +e
    curl -fsSL "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH_W}" \
        -o /usr/local/bin/wings
    WRC=$?
    set -e
    if [[ $WRC -ne 0 || ! -f /usr/local/bin/wings ]]; then
        warn "Download langsung gagal — coba installer community..."
        curl -fsSL "$WINGS_INSTALLER_URL" -o /tmp/wings-install.sh || error_exit 1 "Gagal download wings installer"
        chmod +x /tmp/wings-install.sh
        sed -i 's/^\s*read -r /true #patched /g' /tmp/wings-install.sh 2>/dev/null || true
        export FQDN="$NODE_DOMAIN"
        export EMAIL="$ADMIN_EMAIL"
        export CONFIGURE_FIREWALL="false"
        export CONFIGURE_LETSENCRYPT="false"
        export CONFIGURE_DBHOST="false"
        set +e
        bash /tmp/wings-install.sh 2>&1
        set -e
    fi
    chmod +x /usr/local/bin/wings 2>/dev/null || true
fi

[[ -x /usr/local/bin/wings ]] || error_exit 1 "Wings binary tidak tersedia di /usr/local/bin/wings"

set +e
ensure_ssl_cert "$NODE_DOMAIN"
set -e

NODE_VHOST="/etc/nginx/sites-available/pterodactyl-node.conf"
NODE_CERT_PEM="/etc/letsencrypt/live/${NODE_DOMAIN}/fullchain.pem"
NODE_CERT_KEY="/etc/letsencrypt/live/${NODE_DOMAIN}/privkey.pem"
if [[ ! -f "$NODE_CERT_PEM" ]]; then
    NODE_CERT_PEM="/etc/ssl/${NODE_DOMAIN}.pem"
    NODE_CERT_KEY="/etc/ssl/${NODE_DOMAIN}.key"
fi
if [[ ! -f "$NODE_CERT_PEM" ]]; then
    warn "Cert node tidak ditemukan ($NODE_CERT_PEM) — vhost proxy dilewati, node tetap pakai :$DAEMON_PORT langsung."
else
    info "Setup nginx reverse-proxy node ($NODE_DOMAIN:443 -> 127.0.0.1:$DAEMON_PORT)..."
    cat > "$NODE_VHOST" <<NGINXEOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name ${NODE_DOMAIN};

    access_log /var/log/nginx/pterodactyl-node-access.log;
    error_log  /var/log/nginx/pterodactyl-node-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    ssl_certificate ${NODE_CERT_PEM};
    ssl_certificate_key ${NODE_CERT_KEY};
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-Robots-Tag none;

    location / {
        proxy_pass https://127.0.0.1:${DAEMON_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
NGINXEOF
    ln -sfn "$NODE_VHOST" /etc/nginx/sites-enabled/pterodactyl-node.conf
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx 2>/dev/null || systemctl restart nginx || true
        ok "Reverse-proxy node aktif (443 -> :$DAEMON_PORT)."
    else
        warn "nginx -t gagal setelah tambah vhost node — vhost di-rollback."
        rm -f /etc/nginx/sites-enabled/pterodactyl-node.conf
        nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true
    fi
fi

ok "Wings binary siap."
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

# Panel lokal sering self-signed / LE broken → SELALU -k (insecure SSL)
# supaya tidak exit 60 di step 08.
api_get() {
    local url="$1" out rc
    set +e
    out="$(curl -fsSk --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 90 "${API_HEADERS[@]}" "$url" 2>&1)"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "$out" >&2
        return $rc
    fi
    printf '%s' "$out"
}

api_post() {
    local url="$1" data="$2" out rc
    set +e
    out="$(curl -fsSk --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 90 "${API_HEADERS[@]}" -X POST -d "$data" "$url" 2>&1)"
    rc=$?
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

api_patch() {
    local url="$1" data="$2" out rc
    set +e
    out="$(curl -fsSk --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 90 "${API_HEADERS[@]}" -X PATCH -d "$data" "$url" 2>&1)"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "$out" >&2
        return $rc
    fi
    printf '%s' "$out"
}

set +e
LOCATIONS_JSON="$(api_get "$API_BASE/locations?per_page=100")"
LOC_RC=$?
set -e

if [[ $LOC_RC -ne 0 ]]; then
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
    jq -r --arg ip "$ALLOC_IP" --argjson p "$ALLOCATION_START" '
        .data[]
        | select(.attributes.ip == $ip and .attributes.port == $p)
        | .attributes.port
    ' | head -1
)"

if [[ "$EXISTING_PORT" == "$ALLOCATION_START" ]]; then
    ok "Allocation $ALLOC_IP:$ALLOCATION_START sudah ada."
else
    ALLOC_BODY="$(
        jq -nc \
            --arg ip "$ALLOC_IP" \
            --arg alias "$ALLOC_ALIAS" \
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

set +e
curl -fsSk --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 60 \
    -H "Authorization: Bearer $PLTA" \
    -H "Accept: text/yaml, text/plain, application/vnd.pterodactyl.v1+json" \
    "$API_BASE/nodes/$NODE_ID/configuration" \
    -o "$CONFIG_RAW"
CFG_RC=$?
if [[ $CFG_RC -eq 60 ]]; then
    warn "SSL verify gagal ambil config — retry -k"
    curl -fsSk --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 60 \
        -H "Authorization: Bearer $PLTA" \
        -H "Accept: text/yaml, text/plain, application/vnd.pterodactyl.v1+json" \
        "$API_BASE/nodes/$NODE_ID/configuration" \
        -o "$CONFIG_RAW"
    CFG_RC=$?
fi
set -e
[[ $CFG_RC -eq 0 ]] || error_exit 1 "Gagal ambil config wings dari panel"

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
# 12.5 SINKRONISASI TOKEN NODE (SELF-HEAL)
# =========================================================

run_step "12.5" "[12.5] Sinkronisasi token node (DB panel <-> config.yml)"

TOKEN_ID="$(grep -m1 -E '^[[:space:]]*token_id:' "$CONFIG_YML" | awk '{print $2}')"
TOKEN_PLAIN="$(grep -m1 -E '^[[:space:]]*token:' "$CONFIG_YML" | awk '{print $2}')"
[[ -n "$TOKEN_ID" && -n "$TOKEN_PLAIN" ]] || error_exit 1 "token_id/token tidak ditemukan di config.yml"

cat > "$WORK_DIR/sync_node_token.php" <<PHP
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
\$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
\$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
\$node = Pterodactyl\Models\Node::find(${NODE_ID});
if (!\$node) { fwrite(STDERR, "NODE_NOT_FOUND\n"); exit(1); }
\$node->daemon_token_id = '${TOKEN_ID}';
\$node->daemon_token = encrypt('${TOKEN_PLAIN}');
\$node->save();
\$fresh = Pterodactyl\Models\Node::find(${NODE_ID});
\$attrs = \$fresh->getAttributes();
echo 'DB_TOKEN_ID=' . \$attrs['daemon_token_id'] . "\n";
echo 'DB_TOKEN_MATCH=' . (decrypt(\$attrs['daemon_token']) === '${TOKEN_PLAIN}' ? 'yes' : 'no') . "\n";
PHP
SYNC_OUT="$(cd /var/www/pterodactyl && php "$WORK_DIR/sync_node_token.php" 2>&1)" || { echo "$SYNC_OUT"; error_exit 1 "Gagal sinkron token node"; }
echo "$SYNC_OUT"
grep -q '^DB_TOKEN_MATCH=yes' <<< "$SYNC_OUT" || error_exit 1 "Token DB tidak match dengan config.yml setelah sync"
ok "Token node tersinkron: DB panel = config.yml (terverifikasi)."

cat > "$WORK_DIR/verify_wings.php" <<PHP
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
\$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
\$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
try {
    \$info = app(Pterodactyl\Repositories\Wings\DaemonConfigurationRepository::class)
        ->setNode(Pterodactyl\Models\Node::find(${NODE_ID}))
        ->getSystemInformation();
    echo 'WINGS_OK version=' . \$info['version'] . "\n";
} catch (Throwable \$e) {
    fwrite(STDERR, 'WINGS_FAIL: ' . \$e->getMessage() . "\n");
    exit(1);
}
PHP

# =========================================================
# 13 START WINGS
# =========================================================

run_step "13" "[13] Menjalankan Wings"

if [[ ! -x /usr/local/bin/wings ]]; then
    info "Download wings binary..."
    ARCH_W="amd64"
    case "$(uname -m)" in aarch64|arm64) ARCH_W="arm64" ;; esac
    curl -fsSL "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH_W}" \
        -o /usr/local/bin/wings || error_exit 1 "Gagal download wings binary"
    chmod +x /usr/local/bin/wings
fi

if ! systemctl list-unit-files 2>/dev/null | grep -q '^docker\.service'; then
    if ! command -v docker >/dev/null 2>&1; then
        info "Docker belum ada — install via get.docker.com..."
        set +e
        curl -fsSL https://get.docker.com | sh
        DOCKER_RC=$?
        set -e
        [[ $DOCKER_RC -eq 0 ]] || error_exit 1 "Gagal install Docker"
    fi
fi

systemctl enable docker.socket 2>/dev/null || true
systemctl start docker.socket 2>/dev/null || true
systemctl enable docker 2>/dev/null || true
systemctl start docker 2>/dev/null || true
systemctl enable --now docker 2>/dev/null || true

if ! systemctl is-active --quiet docker 2>/dev/null && ! docker info >/dev/null 2>&1; then
    warn "docker.service belum active, coba start ulang..."
    systemctl reset-failed docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    sleep 2
fi

if ! docker info >/dev/null 2>&1; then
    error_exit 1 "Docker tidak berjalan. Cek: systemctl status docker"
fi
ok "Docker siap."

info "Menulis wings.service..."
cat > /etc/systemd/system/wings.service << 'WINGSEOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service docker.socket network-online.target
Wants=docker.service network-online.target

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

if [[ ! -s /etc/pterodactyl/config.yml ]]; then
    error_exit 1 "config.yml kosong — step 12 gagal?"
fi

sed -i -E "s/^([[:space:]]*)port:[[:space:]]*[0-9]+/\\1port: ${DAEMON_PORT}/" "$CONFIG_YML"

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

if [[ -f /var/www/pterodactyl/.env ]]; then
    sed -i '/^GUZZLE_TIMEOUT=/d' /var/www/pterodactyl/.env
    sed -i '/^GUZZLE_CONNECT_TIMEOUT=/d' /var/www/pterodactyl/.env
    echo 'GUZZLE_TIMEOUT=900' >> /var/www/pterodactyl/.env
    echo 'GUZZLE_CONNECT_TIMEOUT=60' >> /var/www/pterodactyl/.env
fi

# ===== 13b =====
run_step "13b" "[13b] Update node (listen=443) + refresh config Wings"

if [[ -f /etc/nginx/sites-enabled/pterodactyl-node.conf ]]; then
    NODE_UPDATE_BODY='{"daemon_listen":443,"behind_proxy":true}'
    set +e
    NODE_UPD_RAW="$(api_patch "$API_BASE/nodes/$NODE_ID" "$NODE_UPDATE_BODY" 2>&1)"
    NODE_UPD_RC=$?
    set -e
    if [[ $NODE_UPD_RC -eq 0 ]]; then
        ok "Node di-update via API: daemon_listen=443, behind_proxy=true."
    else
        echo "API Node update gagal:"; api_error "$NODE_UPD_RAW"
        warn "Lanjut dengan konfigurasi node yang ada."
    fi

    CONFIG_REFRESH="$WORK_DIR/node-config-refresh.raw"
    set +e
    curl -fsSk --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 60 \
        -H "Authorization: Bearer $PLTA" \
        -H "Accept: text/yaml, text/plain, application/vnd.pterodactyl.v1+json" \
        "$API_BASE/nodes/$NODE_ID/configuration" \
        -o "$CONFIG_REFRESH"
    REFRESH_RC=$?
    if [[ $REFRESH_RC -eq 60 ]]; then
        warn "SSL verify gagal refresh config — retry -k"
        curl -fsSk --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 60 \
            -H "Authorization: Bearer $PLTA" \
            -H "Accept: text/yaml, text/plain, application/vnd.pterodactyl.v1+json" \
            "$API_BASE/nodes/$NODE_ID/configuration" \
            -o "$CONFIG_REFRESH"
        REFRESH_RC=$?
    fi
    set -e
    if [[ $REFRESH_RC -eq 0 ]] && grep -qE '^[[:space:]]*(debug|uuid|token_id|token|api|system|remote):' "$CONFIG_REFRESH"; then
        cp "$CONFIG_REFRESH" "$CONFIG_YML"
        sed -i -E "s/^([[:space:]]*)port:[[:space:]]*[0-9]+/\\1port: ${DAEMON_PORT}/" "$CONFIG_YML"
        if grep -qE '^[[:space:]]*trusted_proxies:' "$CONFIG_YML"; then
            sed -i -E 's|^([[:space:]]*)trusted_proxies:[[:space:]]*\[\][[:space:]]*$|\1trusted_proxies:\n\1- 127.0.0.1\n\1- ::1|' "$CONFIG_YML"
        elif grep -qE '^[[:space:]]*upload_limit:' "$CONFIG_YML"; then
            sed -i '/^[[:space:]]*upload_limit:/a\  trusted_proxies:\n  - 127.0.0.1\n  - ::1' "$CONFIG_YML"
        else
            warn "trusted_proxies tidak bisa di-inject (anchor tidak ditemukan)."
        fi
        if grep -qE '^[[:space:]]*allowed_origins:' "$CONFIG_YML"; then
            sed -i -E "s|^([[:space:]]*)allowed_origins:[[:space:]]*\[\][[:space:]]*\$|\1allowed_origins:\n\1- https://${PANEL_DOMAIN}|" "$CONFIG_YML"
        else
            printf '\nallowed_origins:\n- https://%s\n' "$PANEL_DOMAIN" >> "$CONFIG_YML"
        fi
        chmod 600 "$CONFIG_YML"; chown root:root "$CONFIG_YML"
        ok "config.yml di-regenerate (port=$DAEMON_PORT, trusted_proxies, allowed_origins)."
    else
        warn "Regenerate config.yml gagal — pakai config dari step 12."
    fi

    systemctl restart wings 2>/dev/null || true
    sleep 3
    systemctl is-active --quiet wings || {
        journalctl -u wings -n 50 --no-pager || true
        error_exit 1 "Wings gagal start setelah update konfigurasi"
    }
    ok "Wings restart dengan konfigurasi baru."
else
    NODE_RESET_BODY="$(jq -nc --argjson listen "$DAEMON_PORT" '{daemon_listen:$listen}')"
    set +e
    NODE_RESET_RAW="$(api_patch "$API_BASE/nodes/$NODE_ID" "$NODE_RESET_BODY" 2>&1)"
    NODE_RESET_RC=$?
    set -e
    if [[ $NODE_RESET_RC -eq 0 ]]; then
        ok "Vhost proxy tidak aktif — node di-reset ke :$DAEMON_PORT langsung."
    else
        ok "Vhost proxy tidak aktif — node tetap :$DAEMON_PORT langsung."
    fi
fi

ok "GUZZLE timeout di-refresh."

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
NODE_CHECK_PORT="$DAEMON_PORT"
[[ -f /etc/nginx/sites-enabled/pterodactyl-node.conf ]] && NODE_CHECK_PORT="443"
NODE_CODE="$(curl -ksS --max-time 15 -o /dev/null -w '%{http_code}' "https://$NODE_DOMAIN:$NODE_CHECK_PORT/api/system" 2>/dev/null || echo "000")"
echo "Node HTTP  : $NODE_CODE (port $NODE_CHECK_PORT)"
if [[ "$NODE_CODE" == "401" || "$NODE_CODE" == "403" ]]; then
    ok "Node reachable (auth-required = normal tanpa kredensial)."
else
    warn "Node TIDAK reachable dari server ini (code: $NODE_CODE)."
    warn "Cek: systemctl status wings, nginx, dan firewall provider (port $NODE_CHECK_PORT)."
fi

set +e
VERIFY_OUT="$(cd /var/www/pterodactyl && php "$WORK_DIR/verify_wings.php" 2>&1)"
VERIFY_RC=$?
set -e
echo "$VERIFY_OUT"
[[ $VERIFY_RC -eq 0 ]] || error_exit 1 "Panel tidak bisa mengakses Wings (cek token node / step 12.5)"
# =========================================================
# 15 IMPORT EGG
# =========================================================

run_step "15" "[15] Import Egg — Nusantara Project GOD MODE"

info "Menulis egg.json..."
EGG_B64="eyJfY29tbWVudCI6IkRPIE5PVCBFRElUIiwibWV0YSI6eyJ2ZXJzaW9uIjoiUFRETF92MiIsInVwZGF0ZV91cmwiOm51bGx9LCJleHBvcnRlZF9hdCI6IjIwMjYtMDgtMjRUMDY6MzQ6MDYrMDc6MDAiLCJuYW1lIjoiTnVzYW50YXJhIFByb2plY3QgLSBVTFRJTUFURSBHT0QgTU9ERSAoVW5pZmllZCkiLCJhdXRob3IiOiJyYWZ6aG9zdEByYWZ6aG9zdC5teS5pZCIsImRlc2NyaXB0aW9uIjoiU2F0dSBFZ2cgdW50dWsgbWVuZ3Vhc2FpIHNlbXVhbnlhLiBCaXNhIHN3aXRjaCBhbnRhcmEgWUFSTiAvIE5QTSBsYW5nc3VuZyBkYXJpIHBhbmVsLiIsImZlYXR1cmVzIjpbXSwiZG9ja2VyX2ltYWdlcyI6eyJOb2RlSlMgMjQiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjQiLCJOb2RlSlMgMjMiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjMiLCJOb2RlSlMgMjIiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjIiLCJOb2RlSlMgMjEiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjEiLCJOb2RlSlMgMjAiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjAiLCJOb2RlSlMgMTkiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTkiLCJOb2RlSlMgMTgiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTgiLCJOb2RlSlMgMTciOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTciLCJOb2RlSlMgMTYiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTYiLCJOb2RlSlMgMTUiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTUiLCJQeXRob24gMy4xMiI6ImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnB5dGhvbl8zLjEyIiwiUHl0aG9uIDMuMTEiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpweXRob25fMy4xMSIsIlB5dGhvbiAzLjEwIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6cHl0aG9uXzMuMTAiLCJQeXRob24gMy45IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6cHl0aG9uXzMuOSIsIlB5dGhvbiAzLjgiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpweXRob25fMy44IiwiRGViaWFuIE9TIChVbml2ZXJzYWwpIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6ZGViaWFuIiwiVWJ1bnR1IE9TIChVbml2ZXJzYWwpIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6dWJ1bnR1In0sImZpbGVfZGVueWxpc3QiOltdLCJzdGFydHVwIjoiaWYgW1sgLWQgLmdpdCBdXSAmJiBbWyBcInt7QVVUT19VUERBVEV9fVwiID09IFwiMVwiIF1dOyB0aGVuIGdpdCBwdWxsOyBmaTsgaWYgW1sgISAteiAke0NMT1VERkxBUkVEX1RPS0VOfSBdXTsgdGhlbiBlY2hvIFwiTWVtdWxhaSBDbG91ZGZsYXJlZCBUdW5uZWwuLi5cIjsgd2dldCAtcSBodHRwczovL2dpdGh1Yi5jb20vY2xvdWRmbGFyZS9jbG91ZGZsYXJlZC9yZWxlYXNlcy9sYXRlc3QvZG93bmxvYWQvY2xvdWRmbGFyZWQtbGludXgtYW1kNjQgLU8gY2xvdWRmbGFyZWQgJiYgY2htb2QgK3ggY2xvdWRmbGFyZWQgJiYgLi9jbG91ZGZsYXJlZCB0dW5uZWwgLS1uby1hdXRvdXBkYXRlIHJ1biAtLXRva2VuICR7Q0xPVURGTEFSRURfVE9LRU59ID4gL2Rldi9udWxsIDI+JjEgJiBmaTsgcmVxX2ZpbGU9JHtSRVFVSVJFTUVOVFNfRklMRTotcmVxdWlyZW1lbnRzLnR4dH07IGlmIFsgLWYgL2hvbWUvY29udGFpbmVyLyRyZXFfZmlsZSBdOyB0aGVuIHBpcCBpbnN0YWxsIC1yICRyZXFfZmlsZTsgZmk7IGlmIFsgXCIke1BBQ0tBR0VfTUFOQUdFUn1cIiA9PSBcIm5wbVwiIF07IHRoZW4gaWYgW1sgISAteiAke05PREVfUEFDS0FHRVN9IF1dOyB0aGVuIHllcyBcIlwiIHwgbnBtIGluc3RhbGwgJHtOT0RFX1BBQ0tBR0VTfSAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXQ7IGZpOyBpZiBbWyAhIC16ICR7VU5OT0RFX1BBQ0tBR0VTfSBdXTsgdGhlbiB5ZXMgXCJcIiB8IG5wbSB1bmluc3RhbGwgJHtVTk5PREVfUEFDS0FHRVN9IC0tbm8tZnVuZCAtLW5vLWF1ZGl0OyBmaTsgaWYgWyAtZiAvaG9tZS9jb250YWluZXIvcGFja2FnZS5qc29uIF07IHRoZW4geWVzIFwiXCIgfCBucG0gaW5zdGFsbCAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXQ7IGZpOyBybSAtcmYgLm5wbSAubG9nIC5jYWNoZSAtLWZvcmNlOyBlbHNlIGlmIFtbICEgLXogJHtOT0RFX1BBQ0tBR0VTfSBdXTsgdGhlbiB5ZXMgfCB5YXJuIGFkZCAke05PREVfUEFDS0FHRVN9IC0tbm9uLWludGVyYWN0aXZlIC0taWdub3JlLWVuZ2luZXM7IGZpOyBpZiBbWyAhIC16ICR7VU5OT0RFX1BBQ0tBR0VTfSBdXTsgdGhlbiB5ZXMgfCB5YXJuIHJlbW92ZSAke1VOTk9ERV9QQUNLQUdFU30gLS1ub24taW50ZXJhY3RpdmU7IGZpOyBpZiBbIC1mIC9ob21lL2NvbnRhaW5lci9wYWNrYWdlLmpzb24gXTsgdGhlbiB5ZXMgfCB5YXJuIGluc3RhbGwgLS1ub24taW50ZXJhY3RpdmUgLS1pZ25vcmUtZW5naW5lczsgZmk7IHJtIC1yZiAubnBtIC5sb2cgLmNhY2hlIC55YXJuLWNhY2hlIC0tZm9yY2U7IGZpOyBpZiBbWyAhIC16ICR7Q1VTVE9NX0VOVklST05NRU5UX1ZBUklBQkxFU30gXV07IHRoZW4gdmFycz0kKGVjaG8gJHtDVVNUT01fRU5WSVJPTk1FTlRfVkFSSUFCTEVTfSB8IHRyIFwiO1wiIFwiXFxuXCIpOyBmb3IgbGluZSBpbiAkdmFyczsgZG8gZXhwb3J0ICRsaW5lOyBkb25lIGZpOyBldmFsICR7Q01EX1JVTn07IiwiY29uZmlnIjp7ImZpbGVzIjoie30iLCJzdGFydHVwIjoie1xyXG4gIFwiZG9uZVwiOiBcInJ1bm5pbmdcIlxyXG59IiwibG9ncyI6Int9Iiwic3RvcCI6Il5DIn0sInNjcmlwdHMiOnsiaW5zdGFsbGF0aW9uIjp7InNjcmlwdCI6IiMhL2Jpbi9iYXNoXG5hcHQgdXBkYXRlXG5hcHQgaW5zdGFsbCAteSBnaXQgY3VybCB3Z2V0IGpxIGZpbGUgdW56aXAgbWFrZSBnY2MgZysrIHB5dGhvbjMgcHl0aG9uMy1kZXYgcHl0aG9uMy1waXAgbGlidG9vbFxuaWYgY29tbWFuZCAtdiBucG0gJj4vZGV2L251bGw7IHRoZW4gbnBtIGluc3RhbGwgLWcgeWFybjsgZmlcbm1rZGlyIC1wIC9tbnQvc2VydmVyXG5jZCAvbW50L3NlcnZlclxuaWYgWyBcIiR7VVNFUl9VUExPQUR9XCIgPT0gXCJ0cnVlXCIgXSB8fCBbIFwiJHtVU0VSX1VQTE9BRH1cIiA9PSBcIjFcIiBdOyB0aGVuIGVjaG8gZG9uZTsgZXhpdCAwOyBmaVxuaWYgW1sgJHtHSVRfQUREUkVTU30gIT0gKi5naXQgXV07IHRoZW4gR0lUX0FERFJFU1M9JHtHSVRfQUREUkVTU30uZ2l0OyBmaVxuaWYgWyAteiBcIiR7VVNFUk5BTUV9XCIgXSAmJiBbIC16IFwiJHtBQ0NFU1NfVE9LRU59XCIgXTsgdGhlbiBlY2hvIGFub247IGVsc2UgR0lUX0FERFJFU1M9XCJodHRwczovLyR7VVNFUk5BTUV9OiR7QUNDRVNTX1RPS0VOfUAkKGVjaG8gLWUgJHtHSVRfQUREUkVTU30gfCBjdXQgLWQvIC1mMy0pXCI7IGZpXG5pZiBbIFwiJChscyAtQSAvbW50L3NlcnZlcilcIiBdOyB0aGVuIGlmIFsgLWQgLmdpdCBdICYmIFsgLWYgLmdpdC9jb25maWcgXTsgdGhlbiBPUklHSU49JChnaXQgY29uZmlnIC0tZ2V0IHJlbW90ZS5vcmlnaW4udXJsKTsgaWYgWyBcIiR7T1JJR0lOfVwiID09IFwiJHtHSVRfQUREUkVTU31cIiBdOyB0aGVuIGdpdCBwdWxsOyBmaTsgZmk7IGVsc2UgaWYgWyAteiAke0JSQU5DSH0gXTsgdGhlbiBnaXQgY2xvbmUgJHtHSVRfQUREUkVTU30gLjsgZWxzZSBnaXQgY2xvbmUgLS1zaW5nbGUtYnJhbmNoIC0tYnJhbmNoICR7QlJBTkNIfSAke0dJVF9BRERSRVNTfSAuOyBmaTsgZmlcbmlmIFsgLWYgL21udC9zZXJ2ZXIvcGFja2FnZS5qc29uIF07IHRoZW4gaWYgWyBcIiR7UEFDS0FHRV9NQU5BR0VSfVwiID09IFwibnBtXCIgXTsgdGhlbiBybSAtcmYgbm9kZV9tb2R1bGVzIHBhY2thZ2UtbG9jay5qc29uOyB5ZXMgXCJcIiB8IG5wbSBpbnN0YWxsIC0tcHJvZHVjdGlvbiAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXQ7IGVsc2Ugcm0gLWYgcGFja2FnZS1sb2NrLmpzb247IHllcyB8IHlhcm4gaW5zdGFsbCAtLXByb2R1Y3Rpb24gLS1ub24taW50ZXJhY3RpdmUgLS1pZ25vcmUtZW5naW5lczsgZmk7IGZpXG5yZXFfZmlsZT0ke1JFUVVJUkVNRU5UU19GSUxFOi1yZXF1aXJlbWVudHMudHh0fVxuaWYgWyAtZiAvbW50L3NlcnZlci8kcmVxX2ZpbGUgXTsgdGhlbiBwaXAgaW5zdGFsbCAtciAkcmVxX2ZpbGU7IGZpXG5lY2hvIGluc3RhbGwgY29tcGxldGVcbmV4aXQgMCIsImNvbnRhaW5lciI6ImRlYmlhbjpidWxsc2V5ZS1zbGltIiwiZW50cnlwb2ludCI6ImJhc2gifX0sInZhcmlhYmxlcyI6W3sibmFtZSI6IkdVTkFLQU4gRklMRSBVUExPQUQgTUFOVUFMPyIsImRlc2NyaXB0aW9uIjoiVXBsb2FkIG1hbnVhbCAoMSkgYXRhdSBnaXQgY2xvbmUgKDApLiBSZWluc3RhbGwgU2VydmVyIHVudHVrIGFwcGx5IGdpdC4iLCJlbnZfdmFyaWFibGUiOiJVU0VSX1VQTE9BRCIsImRlZmF1bHRfdmFsdWUiOiIxIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxib29sZWFuIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJQQUNLQUdFIE1BTkFHRVIgKFlBUk4gLyBOUE0pIiwiZGVzY3JpcHRpb24iOiJ5YXJuIGF0YXUgbnBtIiwiZW52X3ZhcmlhYmxlIjoiUEFDS0FHRV9NQU5BR0VSIiwiZGVmYXVsdF92YWx1ZSI6Inlhcm4iLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZ3xpbjp5YXJuLG5wbSIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiRklMRSBVVEFNQSBTQ1JJUFQgKEVOVFJZIEZJTEUpIiwiZGVzY3JpcHRpb24iOiJDb250b2g6IHlhcm4gc3RhcnQsIG5wbSBzdGFydCwgcHl0aG9uIG1haW4ucHkiLCJlbnZfdmFyaWFibGUiOiJDTURfUlVOIiwiZGVmYXVsdF92YWx1ZSI6Inlhcm4gc3RhcnQiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6InJlcXVpcmVkfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiRklMRSBMSUJSQVJZIC8gUkVRVUlSRU1FTlRTIiwiZGVzY3JpcHRpb24iOiJyZXF1aXJlbWVudHMudHh0IiwiZW52X3ZhcmlhYmxlIjoiUkVRVUlSRU1FTlRTX0ZJTEUiLCJkZWZhdWx0X3ZhbHVlIjoicmVxdWlyZW1lbnRzLnR4dCIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJMSU5LIFJFUE9TSVRPUkkgR0lUIChPUFNJT05BTCkiLCJkZXNjcmlwdGlvbiI6IlVSTCBnaXRodWIgcmVwby4gV2FqaWIgUmVpbnN0YWxsIFNlcnZlci4iLCJlbnZfdmFyaWFibGUiOiJHSVRfQUREUkVTUyIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiSW5zdGFsbCBCcmFuY2giLCJkZXNjcmlwdGlvbiI6IkJyYW5jaCBnaXQiLCJlbnZfdmFyaWFibGUiOiJCUkFOQ0giLCJkZWZhdWx0X3ZhbHVlIjoiIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxzdHJpbmciLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkF1dG8gVXBkYXRlIiwiZGVzY3JpcHRpb24iOiIxPXB1bGwgb24gc3RhcnQiLCJlbnZfdmFyaWFibGUiOiJBVVRPX1VQREFURSIsImRlZmF1bHRfdmFsdWUiOiIxIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxib29sZWFuIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJDbG91ZGZsYXJlZCBUb2tlbiIsImRlc2NyaXB0aW9uIjoiVG9rZW4gY2xvdWRmbGFyZSB0dW5uZWwiLCJlbnZfdmFyaWFibGUiOiJDTE9VREZMQVJFRF9UT0tFTiIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiR2l0IFVzZXJuYW1lIiwiZGVzY3JpcHRpb24iOiJHaXQgdXNlciIsImVudl92YXJpYWJsZSI6IlVTRVJOQU1FIiwiZGVmYXVsdF92YWx1ZSI6IiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJHaXQgQWNjZXNzIFRva2VuIiwiZGVzY3JpcHRpb24iOiJHaXQgdG9rZW4iLCJlbnZfdmFyaWFibGUiOiJBQ0NFU1NfVE9LRU4iLCJkZWZhdWx0X3ZhbHVlIjoiIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxzdHJpbmciLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkV4dHJhIE5vZGUgUGFja2FnZXMiLCJkZXNjcmlwdGlvbiI6IlBha2V0IG5wbS95YXJuIGVrc3RyYSAoc3Bhc2kpIiwiZW52X3ZhcmlhYmxlIjoiTk9ERV9QQUNLQUdFUyIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiVW5pbnN0YWxsIE5vZGUgUGFja2FnZXMiLCJkZXNjcmlwdGlvbiI6IlBha2V0IHlhbmcgZGktdW5pbnN0YWxsIiwiZW52X3ZhcmlhYmxlIjoiVU5OT0RFX1BBQ0tBR0VTIiwiZGVmYXVsdF92YWx1ZSI6IiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJDdXN0b20gRW52IFZhcmlhYmxlcyIsImRlc2NyaXB0aW9uIjoiS0VZPXZhbDtLRVkyPXZhbDIiLCJlbnZfdmFyaWFibGUiOiJDVVNUT01fRU5WSVJPTk1FTlRfVkFSSUFCTEVTIiwiZGVmYXVsdF92YWx1ZSI6IiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifV19"
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

SAVE_PASSWORD="$ADMIN_PASSWORD"
if [[ -z "$SAVE_PASSWORD" || "$SAVE_PASSWORD" == "(sudah"* || "$SAVE_PASSWORD" == "(lihat"* ]]; then
    OLD_PW="$(grep -E '^PASSWORD=' "$RESULT_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)"
    if [[ -n "$OLD_PW" && "$OLD_PW" != "(sudah"* && "$OLD_PW" != "(lihat"* ]]; then
        SAVE_PASSWORD="$OLD_PW"
    fi
fi
[[ -z "$SAVE_PASSWORD" ]] && SAVE_PASSWORD="(tidak tersimpan — set manual di panel)"

cat > "$RESULT_FILE" <<DATA
=========================================================
RAFZHOST PTERODACTYL INSTALLATION
=========================================================
PANEL=https://$PANEL_DOMAIN
NODE=https://$NODE_DOMAIN
EMAIL=$ADMIN_EMAIL
USERNAME=$ADMIN_USERNAME
PASSWORD=$SAVE_PASSWORD
FIRSTNAME=$ADMIN_FIRSTNAME
LASTNAME=$ADMIN_LASTNAME
LOCATION_ID=$LOCATION_ID
NODE_ID=$NODE_ID
NEST_ID=$NEST_ID
EGG_ID=$EGG_ID
ALLOCATION=$ALLOC_IP:$ALLOCATION_START-$ALLOCATION_END
ALLOC_ALIAS=$ALLOC_ALIAS
NODE_DAEMON_PORT=$DAEMON_PORT
NODE_BEHIND_PROXY=$([[ -f /etc/nginx/sites-enabled/pterodactyl-node.conf ]] && echo via-nginx-443 || echo direct-$DAEMON_PORT)
PLTA=$PLTA
PLTC=$PLTC
=========================================================
DATA
chmod 600 "$RESULT_FILE"

rm -f /tmp/panel-install.sh /tmp/wings-install.sh /tmp/lib.sh
rm -f /tmp/egg.json /tmp/egg_import.json /tmp/rafz_egg.php
rm -f "$WORK_DIR/create_keys.php" "$WORK_DIR/node-config.raw"
rm -f "$WORK_DIR/sync_node_token.php" "$WORK_DIR/verify_wings.php"
rm -f "$WORK_DIR/node-config-refresh.raw"

banner "INSTALLASI SELESAI"
echo
echo "========================================="
echo "  DATA LOGIN PANEL"
echo "========================================="
echo " URL      : https://$PANEL_DOMAIN"
echo " Email    : $ADMIN_EMAIL"
echo " Username : $ADMIN_USERNAME"
echo " Password : $SAVE_PASSWORD"
echo "========================================="
echo
echo "========================================="
echo "  API KEYS"
echo "========================================="
echo " PLTA     : $PLTA"
echo " PLTC     : $PLTC"
echo "========================================="
echo
echo "========================================="
echo "  NODE / IDS"
echo "========================================="
echo " Node URL : https://$NODE_DOMAIN"
echo " Daemon   : https://$NODE_DOMAIN:$DAEMON_PORT"
echo " Location : $LOCATION_ID"
echo " Node ID  : $NODE_ID"
echo " Nest ID  : $NEST_ID"
echo " Egg ID   : $EGG_ID  ($IMPORT_METHOD)"
echo " Alloc    : $ALLOC_IP:$ALLOCATION_START-$ALLOCATION_END ($ALLOC_ALIAS)"
echo "========================================="
echo
echo " File data : $RESULT_FILE"
echo " Log       : $LOG_FILE"
echo
ok "Panel + Wings + Location + Node + Allocation + Egg selesai."
echo
info "Login: https://$PANEL_DOMAIN  |  $ADMIN_USERNAME / $SAVE_PASSWORD"
