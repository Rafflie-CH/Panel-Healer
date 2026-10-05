#!/usr/bin/env bash
# =========================================================================
# RAFZHOST - GOD MODE INSTALLER (FIXED & TESTED)
# Panel + Wings + Location + Node + Allocation + Egg
# =========================================================================
# v3.6 — Perbaikan menyeluruh SSL (auto-handle rate limit + unified cert):
#   1. UNIFIED SSL CERT: 1 cert Let's Encrypt untuk 2 domain (panel + node)
#      dengan nama "rafzhost-ssl". Hemat kuota LE & Wings langsung pakai LE.
#   2. RATE LIMIT HANDLER: deteksi error "too many certificates"/"rateLimit"
#      otomatis fallback ke STAGING LE, lalu jadwalkan retry via cron.
#   3. AUTO-RETRY CRONJOB: /usr/local/bin/rafz-ssl-retry tiap 6 jam — akan
#      upgrade staging/self-signed ke production LE begitu rate limit reset.
#   4. AUTO-REUSE: kalau cert existing sudah cover kedua domain, dipakai ulang.
#   5. Wings TIDAK fallback ke self-signed kecuali terpaksa (browser hijau).
#   6. Verifikasi cert coverage (SAN) + warning kritis di akhir.
# =========================================================================
# v3.3 — AUTO-PATCH panel .env (TRUSTED_PROXIES, SESSION_SECURE_COOKIE) +
#        nginx panel (HTTP_X_FORWARDED_PROTO) + verifikasi mixed content.
# =========================================================================

set -Eeuo pipefail

export HOME="${HOME:-/root}"
export COMPOSER_HOME="${COMPOSER_HOME:-$HOME/.composer}"
export COMPOSER_ALLOW_SUPERUSER=1
mkdir -p "$COMPOSER_HOME"

INSTALLER_BASE="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer"
INSTALLER_VERSION="v1.3.0"
PANEL_INSTALLER_URL="$INSTALLER_BASE/$INSTALLER_VERSION/installers/panel.sh"
LIB_URL="$INSTALLER_BASE/$INSTALLER_VERSION/lib/lib.sh"
SELF_URL="${GODMODE_SELF_URL:-https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh}"

LOG_FILE="/root/ptero_install.log"
WORK_DIR="/root/.rafz-ptero-installer"
RESULT_FILE="/root/rafzhost-panel-data.txt"
SSL_CONF="/etc/rafzhost-ssl.conf"
SSL_RETRY_LOG="/var/log/rafzhost-ssl-retry.log"

mkdir -p "$WORK_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

banner()  { echo "========================================================="; printf ' %-55s\n' "$1"; echo "========================================================="; }
ok()      { echo "[✓] $1"; }
info()    { echo "[*] $1"; }
warn()    { echo "[!] $1"; }
crit()    { echo "[‼] $1"; }

STEP="Inisialisasi"
error_exit() {
    local rc=${1:-1} msg="${2:-Unknown error}"
    echo
    echo "========================================================="
    echo " INSTALLER GAGAL"
    echo "========================================================="
    echo "Step      : ${STEP:-Tidak diketahui}"
    echo "Exit code : $rc"
    echo "Pesan     : $msg"
    echo "Log       : $LOG_FILE"
    tail -25 "$LOG_FILE" 2>/dev/null || true
    echo "========================================================="
    exit "$rc"
}
trap 'rc=$?; error_exit "$rc" "Command gagal di step: ${STEP:-unknown}"' ERR

# =========================================================================
# 00b INPUT INTERAKTIF
# =========================================================================
ask() {
    local __var="$1" __prompt="$2" __def="${3:-}" __secret="${4:-0}" __val=""
    if [[ -n "$__def" ]]; then
        if [[ "$__secret" == "1" ]]; then printf "%s [tersimpan]: " "$__prompt"
        else printf "%s [%s]: " "$__prompt" "$__def"; fi
    else printf "%s: " "$__prompt"; fi
    if ! read -r __val 2>/dev/null < /dev/tty; then __val=""; fi
    [[ -z "$__val" ]] && __val="$__def"
    printf -v "$__var" '%s' "$__val"
}

PANEL_DOMAIN="${PANEL_DOMAIN:-}"
NODE_DOMAIN="${NODE_DOMAIN:-}"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_USERNAME="${ADMIN_USERNAME:-}"
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-}"
ADMIN_LASTNAME="${ADMIN_LASTNAME:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

load_env_defaults() {
    [[ -f /root/godmode.env ]] || return 0
    local k v
    while IFS='=' read -r k v; do
        case "$k" in
            PANEL_DOMAIN) [[ -z "$PANEL_DOMAIN" ]] && PANEL_DOMAIN="${v//\"/}" ;;
            NODE_DOMAIN)  [[ -z "$NODE_DOMAIN" ]] && NODE_DOMAIN="${v//\"/}" ;;
            SERVER_HOSTNAME) [[ -z "$SERVER_HOSTNAME" ]] && SERVER_HOSTNAME="${v//\"/}" ;;
            ADMIN_EMAIL)  [[ -z "$ADMIN_EMAIL" ]] && ADMIN_EMAIL="${v//\"/}" ;;
            ADMIN_USERNAME) [[ -z "$ADMIN_USERNAME" ]] && ADMIN_USERNAME="${v//\"/}" ;;
            ADMIN_FIRSTNAME) [[ -z "$ADMIN_FIRSTNAME" ]] && ADMIN_FIRSTNAME="${v//\"/}" ;;
            ADMIN_LASTNAME) [[ -z "$ADMIN_LASTNAME" ]] && ADMIN_LASTNAME="${v//\"/}" ;;
            ADMIN_PASSWORD) [[ -z "$ADMIN_PASSWORD" ]] && ADMIN_PASSWORD="${v//\"/}" ;;
        esac
    done < <(grep -E '^(PANEL_DOMAIN|NODE_DOMAIN|SERVER_HOSTNAME|ADMIN_EMAIL|ADMIN_USERNAME|ADMIN_FIRSTNAME|ADMIN_LASTNAME|ADMIN_PASSWORD)=' /root/godmode.env 2>/dev/null || true)
}
load_env_defaults

SERVER_HOSTNAME="${SERVER_HOSTNAME:-$(hostname 2>/dev/null || true)}"
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-admin}"
ADMIN_LASTNAME="${ADMIN_LASTNAME:-admin}"

# =========================================================================
# 00c DETEKSI SISA INSTALL
# =========================================================================
PANEL_INSTALLED=0
WINGS_BINARY=0
WINGS_CONFIG=0
[[ -f /var/www/pterodactyl/artisan ]] && PANEL_INSTALLED=1
[[ -x /usr/local/bin/wings ]] && WINGS_BINARY=1
[[ -s /etc/pterodactyl/config.yml ]] && WINGS_CONFIG=1

banner "RAFZHOST x DEKZYMARKET - GOD MODE INSTALLER v3.5"
echo
echo "----- STATUS SISTEM -----"
echo "Panel  : $([ $PANEL_INSTALLED -eq 1 ] && echo 'SUDAH TERPASANG' || echo 'BELUM')"
if [[ $WINGS_CONFIG -eq 1 ]]; then echo "Wings  : SUDAH TERPASANG"
elif [[ $WINGS_BINARY -eq 1 ]]; then echo "Wings  : SISA BINARY (akan di-setup ulang)"
else echo "Wings  : BELUM"; fi
command -v docker >/dev/null 2>&1 && echo "Docker : SUDAH TERPASANG" || echo "Docker : BELUM"
echo "-------------------------"
echo

# =========================================================================
# 00d KUMPUL INPUT
# =========================================================================
info "Isi data di bawah (tekan Enter untuk pakai nilai dalam kurung)."
echo
ask PANEL_DOMAIN "Domain Panel" "$PANEL_DOMAIN"
ask NODE_DOMAIN "Domain Node" "$NODE_DOMAIN"
ask SERVER_HOSTNAME "Hostname VPS (kosongkan = pakai sekarang)" "${SERVER_HOSTNAME:-}"
ask ADMIN_EMAIL "Email Admin" "${ADMIN_EMAIL:-}"
ask ADMIN_USERNAME "Username Admin" "${ADMIN_USERNAME:-admin}"
ask ADMIN_FIRSTNAME "Nama Depan" "${ADMIN_FIRSTNAME:-Admin}"
ask ADMIN_LASTNAME "Nama Belakang" "${ADMIN_LASTNAME:-Rafz}"
ask ADMIN_PASSWORD "Password Admin" "${ADMIN_PASSWORD:-}" 1

[[ -n "$PANEL_DOMAIN" ]]   || error_exit 1 "Domain Panel tidak boleh kosong."
[[ -n "$NODE_DOMAIN" ]]    || error_exit 1 "Domain Node tidak boleh kosong."
[[ -n "$SERVER_HOSTNAME" ]] || error_exit 1 "Hostname VPS tidak boleh kosong."
[[ -n "$ADMIN_EMAIL" ]]    || error_exit 1 "Email Admin tidak boleh kosong."
[[ -n "$ADMIN_USERNAME" ]] || error_exit 1 "Username Admin tidak boleh kosong."
[[ -n "$ADMIN_PASSWORD" ]] || error_exit 1 "Password Admin tidak boleh kosong."
[[ "$PANEL_DOMAIN" != "$NODE_DOMAIN" ]] || error_exit 1 "Domain Panel dan Node tidak boleh sama."

# =========================================================================
# 00e HAPUS SISA INSTALL LAMA
# =========================================================================
if [[ $PANEL_INSTALLED -eq 1 || $WINGS_BINARY -eq 1 || $WINGS_CONFIG -eq 1 ]]; then
    warn "Terdeteksi sisa install lama — membersihkan (force reinstall)..."
    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
    rm -f /etc/systemd/system/wings.service
    systemctl stop pteroq nginx 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/pterodactyl-node.conf /etc/nginx/sites-available/pterodactyl-node.conf
    rm -f /etc/nginx/sites-enabled/default
    rm -rf /var/www/pterodactyl /etc/pterodactyl
    rm -f /usr/local/bin/wings
    rm -f "$RESULT_FILE"
    mariadb -u root -e "DROP DATABASE IF EXISTS panel;" 2>/dev/null || true
    mariadb -u root -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1'; DROP USER IF EXISTS 'pterodactyl'@'localhost';" 2>/dev/null || true
    info "Sisa install lama dihapus (termasuk DB panel)."
fi

# =========================================================================
# 00f HOSTNAME VPS
# =========================================================================
STEP="00f Hostname"
if [[ "$(hostname)" != "$SERVER_HOSTNAME" ]]; then
    hostname "$SERVER_HOSTNAME" 2>/dev/null || true
    command -v hostnamectl >/dev/null 2>&1 && hostnamectl set-hostname "$SERVER_HOSTNAME" 2>/dev/null || true
    if grep -qE '^[[:space:]]*127\.0\.1\.1[[:space:]]' /etc/hosts 2>/dev/null; then
        sed -i -E "s|^([[:space:]]*127\.0\.1\.1[[:space:]]+).*|\1${SERVER_HOSTNAME}|" /etc/hosts 2>/dev/null || true
    fi
    ok "Hostname VPS di-set ke: $SERVER_HOSTNAME"
else
    ok "Hostname VPS sudah: $SERVER_HOSTNAME"
fi

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

# Unified cert config (v3.4)
CERT_NAME="rafzhost-ssl"
CERT_LIVE="/etc/letsencrypt/live/${CERT_NAME}"
CERT_STAGING_LIVE="/etc/letsencrypt/live/${CERT_NAME}-staging"

info "Mode      : INSTALL BARU"
info "Panel     : $PANEL_DOMAIN"
info "Node      : $NODE_DOMAIN"
info "Admin     : $ADMIN_USERNAME <$ADMIN_EMAIL>"
info "Ports     : $ALLOCATION_START-$ALLOCATION_END"
info "SSL Mode  : UNIFIED (1 cert untuk 2 domain)"
echo

# =========================================================================
# 01 SISTEM
# =========================================================================
STEP="01 Sistem"
banner "[01] Pengecekan sistem"
. /etc/os-release
ARCH="$(uname -m)"
case "$ARCH" in x86_64|amd64|aarch64|arm64) ;; *) error_exit 1 "Architecture tidak didukung: $ARCH" ;; esac
case "$ID:$VERSION_ID" in
    ubuntu:22.04|ubuntu:24.04|debian:11|debian:12|debian:13) ;;
    *) error_exit 1 "OS tidak didukung: $PRETTY_NAME" ;;
esac
echo "OS: $ID $VERSION_ID | Arch: $ARCH"
ok "OS dan architecture terdeteksi."

# =========================================================================
# 02 DEPENDENCY
# =========================================================================
STEP="02 Dependency"
banner "[02] Install dependency dasar"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 DEBCONF_NONINTERACTIVE_SEEN=true COMPOSER_ALLOW_SUPERUSER=1
apt-get update --allow-releaseinfo-change -y || error_exit 1 "apt-get update gagal"
apt-get install -y ca-certificates curl wget gnupg jq unzip git redis-server openssl dnsutils lsof python3 \
    || error_exit 1 "Gagal install dependency dasar"
ok "Dependency dasar siap."

# =========================================================================
# 03 PUBLIC IP
# =========================================================================
STEP="03 Deteksi IP"
banner "[03] Deteksi IP VPS"
PUBLIC_IP=""
for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com https://checkip.amazonaws.com; do
    tmp="$(curl -4fsS --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    case "$tmp" in *[!0-9.]*|'') continue ;; esac
    dots="${tmp//[^.]/}"
    [[ ${#dots} -eq 3 ]] && { PUBLIC_IP="$tmp"; break; }
done
if [[ -z "$PUBLIC_IP" ]]; then
    tmp="$(hostname -I 2>/dev/null | tr ' ' '\n' | head -1 | tr -d '[:space:]' || true)"
    case "$tmp" in *[!0-9.]*|'') ;; *) dots="${tmp//[^.]/}"; [[ ${#dots} -eq 3 ]] && PUBLIC_IP="$tmp" ;; esac
fi
[[ -n "$PUBLIC_IP" ]] || error_exit 1 "Gagal deteksi IPv4 publik"
case "$PUBLIC_IP" in *[!0-9.]*|'') error_exit 1 "IPv4 tidak valid: $PUBLIC_IP" ;; esac
echo "VPS IPv4: $PUBLIC_IP"
ok "IP terdeteksi."
ALLOC_IP="$PUBLIC_IP"
ALLOC_ALIAS="$NODE_NAME"

# =========================================================================
# 04 DNS
# =========================================================================
STEP="04 DNS"
banner "[04] Pengecekan DNS"
PANEL_DNS="$(dig +short A "$PANEL_DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9.]+$' | tail -1 || true)"
NODE_DNS="$(dig +short A "$NODE_DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9.]+$' | tail -1 || true)"
[[ -n "$PANEL_DNS" ]] || PANEL_DNS="$(dig +short A "$PANEL_DOMAIN" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' | tail -1 || true)"
[[ -n "$NODE_DNS" ]] || NODE_DNS="$(dig +short A "$NODE_DOMAIN" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' | tail -1 || true)"
echo "Panel DNS: ${PANEL_DNS:-TIDAK ADA} | Node DNS: ${NODE_DNS:-TIDAK ADA} | VPS: $PUBLIC_IP"
[[ "$PANEL_DNS" == "$PUBLIC_IP" ]] || error_exit 1 "DNS Panel tidak match ($PANEL_DOMAIN => ${PANEL_DNS:-NONE})"
[[ "$NODE_DNS" == "$PUBLIC_IP" ]] || error_exit 1 "DNS Node tidak match ($NODE_DOMAIN => ${NODE_DNS:-NONE})"
ok "DNS publik sesuai IP VPS."
sed -i "/[[:space:]]$PANEL_DOMAIN[[:space:]]/d" /etc/hosts 2>/dev/null || true
sed -i "/[[:space:]]$NODE_DOMAIN[[:space:]]/d" /etc/hosts 2>/dev/null || true

# =========================================================================
# SSL HELPERS v3.4 — UNIFIED CERT + RATE LIMIT HANDLER
# =========================================================================

# Cek apakah cert PEM meng-cover semua domain yang diminta
cert_covers_domains() {
    local cert_pem="$1"; shift
    [[ -s "$cert_pem" ]] || return 1
    local san_text
    san_text="$(openssl x509 -in "$cert_pem" -noout -text 2>/dev/null | \
                awk '/Subject Alternative Name/,/^ *$/' || true)"
    local d
    for d in "$@"; do
        echo "$san_text" | grep -q "DNS:${d}\b" || return 1
    done
    return 0
}

# Deteksi error rate limit Let's Encrypt dari output certbot
is_rate_limited() {
    grep -qiE "too many (certificates|requests|failed)|rate ?limit|rateLimit|urn:ietf:params:acme:error:rateLimited" <<<"$1"
}

# Install plugin certbot-nginx kalau belum ada
ensure_certbot_nginx_plugin() {
    if ! certbot plugins 2>/dev/null | grep -qE '^\* nginx$'; then
        info "Install plugin certbot-nginx..."
        apt-get update -o=Dpkg::Use-Pty=0 >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3-certbot-nginx >/dev/null 2>&1 || true
    fi
}

# Bikin server block nginx minimal untuk ACME challenge (kalau belum ada)
ensure_acme_nginx_block() {
    local domain="$1"
    # Cek apakah sudah ada server block dengan domain ini
    if grep -rqs "server_name.*\b${domain}\b" /etc/nginx/sites-enabled/ 2>/dev/null; then
        return 0
    fi
    local conf="/etc/nginx/sites-available/rafz-acme-${domain}.conf"
    cat > "$conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$server_name\$request_uri; }
}
EOF
    ln -sf "$conf" /etc/nginx/sites-enabled/
    mkdir -p /var/www/html/.well-known/acme-challenge
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
}

# Coba dapatkan unified cert untuk kedua domain
# Return: 0 = production LE, 2 = staging LE, 1 = gagal total (rate limit / error)
obtain_unified_cert() {
    local d1="$1" d2="$2"
    local out rc=0

    ensure_certbot_nginx_plugin
    ensure_acme_nginx_block "$d1"
    ensure_acme_nginx_block "$d2"
    mkdir -p /var/www/html/.well-known/acme-challenge

    # CRITICAL: nginx config dari panel installer sering pointing ke /etc/ssl/<domain>.pem
    # yang BELUM ada → nginx -t gagal → certbot --nginx gagal. Buat placeholder dulu.
    preflight_nginx_ssl_certs

    # ---- ATTEMPT 1: Production LE via nginx plugin ----
    info "Meminta cert Let's Encrypt (production) untuk: $d1, $d2"
    rc=0
    out="$(certbot certonly --nginx -d "$d1" -d "$d2" \
        --non-interactive --agree-tos --register-unsafely-without-email \
        --keep-until-expiring --expand \
        --cert-name "$CERT_NAME" 2>&1)" || rc=$?

    if [[ $rc -eq 0 && -s "${CERT_LIVE}/fullchain.pem" ]]; then
        ok "Cert LE production didapat (nama: $CERT_NAME)"
        return 0
    fi

    # ---- Deteksi rate limit ----
    if is_rate_limited "$out"; then
        crit "Let's Encrypt RATE LIMIT terdeteksi!"
        echo "$out" | grep -iE "too many|rate ?limit|retry after|when.*next" | head -3 || true
        echo
        warn "Beralih ke STAGING Let's Encrypt (TIDAK dipercaya browser)..."
        warn "Cronjob akan auto-retry production tiap 6 jam."
        rc=0
        out="$(certbot certonly --nginx -d "$d1" -d "$d2" \
            --non-interactive --agree-tos --register-unsafely-without-email \
            --keep-until-expiring --expand --staging \
            --cert-name "${CERT_NAME}-staging" 2>&1)" || rc=$?
        if [[ $rc -eq 0 && -s "${CERT_STAGING_LIVE}/fullchain.pem" ]]; then
            warn "Cert STAGING didapat — panel & wings akan tampil 'Not Secure' sampai retry sukses."
            return 2
        fi
        # staging juga gagal → coba standalone staging lalu return 1
        warn "Staging nginx plugin gagal — coba standalone staging..."
        systemctl stop nginx 2>/dev/null || true
        rc=0
        out="$(certbot certonly --standalone -d "$d1" -d "$d2" \
            --non-interactive --agree-tos --register-unsafely-without-email \
            --keep-until-expiring --expand --staging \
            --cert-name "${CERT_NAME}-staging" 2>&1)" || rc=$?
        systemctl start nginx 2>/dev/null || true
        if [[ $rc -eq 0 && -s "${CERT_STAGING_LIVE}/fullchain.pem" ]]; then
            warn "Cert STAGING didapat via standalone."
            return 2
        fi
        warn "Staging juga gagal — pakai self-signed sementara."
        return 1
    fi

    # ---- Fallback: SELALU coba standalone kalau nginx plugin gagal (termasuk BIO_new_file / nginx -t) ----
    warn "Certbot --nginx gagal (rc=$rc). Fallback ke --standalone..."
    echo "$out" | tail -8 || true
    systemctl stop nginx 2>/dev/null || true
    sleep 1
    rc=0
    out="$(certbot certonly --standalone -d "$d1" -d "$d2" \
        --non-interactive --agree-tos --register-unsafely-without-email \
        --keep-until-expiring --expand \
        --cert-name "$CERT_NAME" 2>&1)" || rc=$?
    systemctl start nginx 2>/dev/null || true
    if [[ $rc -eq 0 && -s "${CERT_LIVE}/fullchain.pem" ]]; then
        ok "Cert LE production didapat via standalone."
        return 0
    fi
    if is_rate_limited "$out"; then
        crit "Rate limit juga kena di standalone — pakai self-signed sementara."
        return 1
    fi

    warn "Certbot gagal total. Error terakhir:"
    echo "$out" | tail -8 || true
    return 1
}

# Buat self-signed cert (fallback terakhir) + install ke CA store
make_selfsigned_cert() {
    local domain="$1"
    local base="/etc/ssl/.selfsigned-${domain}"
    mkdir -p /etc/ssl
    if [[ ! -s "${base}.pem" ]]; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "${base}.key" -out "${base}.pem" \
            -subj "/CN=${domain}" >/dev/null 2>&1 \
            || { warn "openssl self-signed gagal untuk $domain"; return 1; }
    fi
    cp -f "${base}.pem" "/usr/local/share/ca-certificates/rafz-${domain}.crt" 2>/dev/null || true
    command -v update-ca-certificates >/dev/null 2>&1 && update-ca-certificates >/dev/null 2>&1 || true
}

# Pastikan semua path ssl_certificate di nginx ADA filenya (placeholder self-signed)
# supaya nginx -t sukses sebelum certbot --nginx jalan.
preflight_nginx_ssl_certs() {
    local confs paths path dir domain base
    confs=$(find /etc/nginx -type f \( -name '*.conf' -o -name '*pterodactyl*' \) 2>/dev/null || true)
    [[ -z "$confs" ]] && return 0
    paths=$(grep -hE '^\s*ssl_certificate\s+' $confs 2>/dev/null | awk '{print $2}' | tr -d ';' | sort -u || true)
    for path in $paths; do
        [[ -z "$path" || "$path" == *"letsencrypt"* ]] && continue
        if [[ ! -s "$path" ]]; then
            dir=$(dirname "$path")
            mkdir -p "$dir"
            domain=$(basename "$path" | sed -E 's/\.(pem|crt)$//')
            base="/etc/ssl/.selfsigned-${domain}"
            if [[ ! -s "${base}.pem" ]]; then
                openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                    -keyout "${base}.key" -out "${base}.pem" \
                    -subj "/CN=${domain}" >/dev/null 2>&1 || true
            fi
            # copy placeholder ke path yang diminta nginx
            [[ -s "${base}.pem" ]] && cp -f "${base}.pem" "$path"
            # key pairing
            local keypath
            keypath=$(grep -hE "^\s*ssl_certificate_key\s+" $confs 2>/dev/null | awk '{print $2}' | tr -d ';' | grep -F "$domain" | head -1 || true)
            if [[ -n "$keypath" && ! -s "$keypath" && -s "${base}.key" ]]; then
                mkdir -p "$(dirname "$keypath")"
                cp -f "${base}.key" "$keypath"
            fi
            # juga symlink standar
            ln -sfn "${base}.pem" "/etc/ssl/${domain}.pem" 2>/dev/null || true
            ln -sfn "${base}.key" "/etc/ssl/${domain}.key" 2>/dev/null || true
            info "Placeholder cert dibuat: $path"
        fi
    done
    # Pastikan path standar panel/node juga ada
    for domain in ${PANEL_DOMAIN:-} ${NODE_DOMAIN:-}; do
        [[ -z "$domain" ]] && continue
        if [[ ! -s "/etc/ssl/${domain}.pem" ]]; then
            make_selfsigned_cert "$domain" 2>/dev/null || {
                openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                    -keyout "/etc/ssl/.selfsigned-${domain}.key" \
                    -out "/etc/ssl/.selfsigned-${domain}.pem" \
                    -subj "/CN=${domain}" >/dev/null 2>&1 || true
            }
            ln -sfn "/etc/ssl/.selfsigned-${domain}.pem" "/etc/ssl/${domain}.pem" 2>/dev/null || true
            ln -sfn "/etc/ssl/.selfsigned-${domain}.key" "/etc/ssl/${domain}.key" 2>/dev/null || true
        fi
    done
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
}


# Tulis config untuk cronjob retry
write_ssl_conf() {
    cat > "$SSL_CONF" <<EOF
PANEL_DOMAIN=${PANEL_DOMAIN}
NODE_DOMAIN=${NODE_DOMAIN}
CERT_NAME=${CERT_NAME}
ADMIN_EMAIL=${ADMIN_EMAIL}
EOF
    chmod 600 "$SSL_CONF"
}

# Pasang script retry + cronjob 6 jam
install_ssl_retry_cron() {
    cat > /usr/local/bin/rafz-ssl-retry <<'RETRY_EOF'
#!/usr/bin/env bash
# RAFZHOST SSL auto-retry — upgrade staging/self-signed → production LE
set -uo pipefail
LOG="/var/log/rafzhost-ssl-retry.log"
CONF="/etc/rafzhost-ssl.conf"
[[ -f "$CONF" ]] || exit 0
# shellcheck disable=SC1090
. "$CONF"

echo "[$(date '+%F %T')] Cek cert $CERT_NAME..." >> "$LOG"

# Sudah production LE? Skip.
if [[ -s "/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem" ]]; then
    # Verifikasi masih valid & bukan staging
    if openssl x509 -in "/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem" -noout -issuer 2>/dev/null | grep -q "(STAGING)"; then
        echo "  → masih STAGING, coba production..." >> "$LOG"
    else
        echo "  → sudah production LE, skip." >> "$LOG"
        exit 0
    fi
fi

# Coba production
OUT="$(certbot certonly --nginx -d "$PANEL_DOMAIN" -d "$NODE_DOMAIN" \
    --non-interactive --agree-tos --register-unsafely-without-email \
    --keep-until-expiring --expand \
    --cert-name "$CERT_NAME" 2>&1)" || true

if [[ -s "/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem" ]]; then
    echo "  → production LE BERHASIL ✅" >> "$LOG"
    # Reload nginx panel + restart wings
    systemctl reload nginx 2>/dev/null || true
    systemctl restart wings 2>/dev/null || true
    # Sinkron cert node (kalau wings pakai path berbeda)
    if [[ -f /etc/pterodactyl/config.yml ]]; then
        sed -i \
            -e "s|^\( *\)cert:.*|\1cert: /etc/letsencrypt/live/${CERT_NAME}/fullchain.pem|" \
            -e "s|^\( *\)key:.*|\1key: /etc/letsencrypt/live/${CERT_NAME}/privkey.pem|" \
            /etc/pterodactyl/config.yml
        systemctl restart wings 2>/dev/null || true
    fi
else
    if echo "$OUT" | grep -qiE "too many|rate ?limit"; then
        echo "  → masih rate limit, coba lagi 6 jam lagi." >> "$LOG"
    else
        echo "  → gagal: $(echo "$OUT" | tail -1)" >> "$LOG"
    fi
fi
RETRY_EOF
    chmod +x /usr/local/bin/rafz-ssl-retry
    ( crontab -l 2>/dev/null | grep -vF '/usr/local/bin/rafz-ssl-retry' || true; \
      echo '0 */6 * * * /usr/local/bin/rafz-ssl-retry >> /var/log/rafzhost-ssl-retry.log 2>&1' ) | crontab - \
      || warn "Gagal pasang cronjob SSL retry"
    ok "Cronjob SSL retry terpasang (tiap 6 jam)."
}

# =========================================================================
# 05 PANEL
# =========================================================================
STEP="05 Panel"
banner "[05] Install Pterodactyl Panel"
DB_PASSWORD="$(openssl rand -hex 24)"
export FQDN="$PANEL_DOMAIN" MYSQL_DB="panel" MYSQL_USER="pterodactyl" MYSQL_PASSWORD="$DB_PASSWORD"
export timezone="Asia/Jakarta" telemetry="false"
export ASSUME_SSL="true" CONFIGURE_LETSENCRYPT="false" CONFIGURE_FIREWALL="false"
export email="$ADMIN_EMAIL" user_email="$ADMIN_EMAIL" user_username="$ADMIN_USERNAME"
export user_firstname="$ADMIN_FIRSTNAME" user_lastname="$ADMIN_LASTNAME" user_password="$ADMIN_PASSWORD"

info "Mengambil installer resmi $INSTALLER_VERSION..."
curl -fsSL "$LIB_URL" -o /tmp/lib.sh || error_exit 1 "Gagal download lib.sh"
curl -fsSL "$PANEL_INSTALLER_URL" -o /tmp/panel-install.sh || error_exit 1 "Gagal download panel installer"
chmod +x /tmp/panel-install.sh

info "Menjalankan installer Panel..."
bash /tmp/panel-install.sh || error_exit 1 "Panel installer gagal"

# --- FIX CRONJOB (anti-duplikat) ---
STEP="05b Cronjob"
info "Setup cronjob schedule:run (anti-duplikat)..."
( crontab -l 2>/dev/null | grep -vF 'pterodactyl/artisan schedule:run' || true; \
  echo '* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1' ) | crontab - \
  || error_exit 1 "Gagal pasang cronjob"
ok "Cronjob terpasang (tepat 1 entri)."

rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Panel installer (ASSUME_SSL=true) sering bikin vhost HTTPS yang pointing ke
# /etc/ssl/<domain>.pem yang belum ada → nginx -t gagal. Placeholder dulu.
info "Preflight SSL placeholder setelah panel install..."
preflight_nginx_ssl_certs || true

# =========================================================================
# 05c SSL UNIFIED (PANEL + NODE) — v3.5
# =========================================================================
STEP="05c SSL Unified"
banner "[05c] Setup SSL UNIFIED (panel + node)"
write_ssl_conf

SSL_MODE="self-signed"   # default fallback
if [[ -s "${CERT_LIVE}/fullchain.pem" ]] && cert_covers_domains "${CERT_LIVE}/fullchain.pem" "$PANEL_DOMAIN" "$NODE_DOMAIN"; then
    ok "Cert unified existing ditemukan & valid ($CERT_NAME) — reuse."
    SSL_MODE="production"
else
    set +e
    obtain_unified_cert "$PANEL_DOMAIN" "$NODE_DOMAIN"
    SSL_RC=$?
    set -e
    case "$SSL_RC" in
        0) SSL_MODE="production" ;;
        2) SSL_MODE="staging" ;;
        *) SSL_MODE="self-signed" ;;
    esac
fi

# Path cert sesuai mode
if [[ "$SSL_MODE" == "production" ]]; then
    PANEL_CERT_PEM="${CERT_LIVE}/fullchain.pem"
    PANEL_CERT_KEY="${CERT_LIVE}/privkey.pem"
    NODE_CERT_PEM="${CERT_LIVE}/fullchain.pem"
    NODE_CERT_KEY="${CERT_LIVE}/privkey.pem"
    ok "Panel + Wings akan pakai LE PRODUCTION cert: $CERT_NAME"
elif [[ "$SSL_MODE" == "staging" ]]; then
    PANEL_CERT_PEM="${CERT_STAGING_LIVE}/fullchain.pem"
    PANEL_CERT_KEY="${CERT_STAGING_LIVE}/privkey.pem"
    NODE_CERT_PEM="${CERT_STAGING_LIVE}/fullchain.pem"
    NODE_CERT_KEY="${CERT_STAGING_LIVE}/privkey.pem"
    warn "Pakai STAGING cert — browser akan tampil warning. Cronjob akan retry production."
else
    # Self-signed untuk masing-masing domain
    make_selfsigned_cert "$PANEL_DOMAIN"
    make_selfsigned_cert "$NODE_DOMAIN"
    PANEL_CERT_PEM="/etc/ssl/.selfsigned-${PANEL_DOMAIN}.pem"
    PANEL_CERT_KEY="/etc/ssl/.selfsigned-${PANEL_DOMAIN}.key"
    NODE_CERT_PEM="/etc/ssl/.selfsigned-${NODE_DOMAIN}.pem"
    NODE_CERT_KEY="/etc/ssl/.selfsigned-${NODE_DOMAIN}.key"
    crit "SSL gagal — pakai SELF-SIGNED. Browser akan tampil warning!"
    crit "Cronjob auto-retry sudah dijadwalkan (tiap 6 jam)."
fi

# Symlink standar /etc/ssl/<domain>.pem biar kompatibel config lama
ln -sfn "$PANEL_CERT_PEM" "/etc/ssl/${PANEL_DOMAIN}.pem"
ln -sfn "$PANEL_CERT_KEY" "/etc/ssl/${PANEL_DOMAIN}.key"
ln -sfn "$NODE_CERT_PEM" "/etc/ssl/${NODE_DOMAIN}.pem"
ln -sfn "$NODE_CERT_KEY" "/etc/ssl/${NODE_DOMAIN}.key"

# Fix permission LE (wings butuh read)
chmod 755 /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true

# Pasang cronjob retry (selalu, biar auto-upgrade kalau staging/self-signed)
install_ssl_retry_cron

# Update nginx panel pakai unified cert (path sudah otomatis dari installer LE,
# tapi kalau self-signed kita harus patch manual)
PANEL_NGINX_CONF="/etc/nginx/sites-available/pterodactyl.conf"
if [[ -f "$PANEL_NGINX_CONF" ]]; then
    # Ganti path cert ke unified
    sed -i -E "s|^(\s*ssl_certificate\s+).*|\1${PANEL_CERT_PEM};|" "$PANEL_NGINX_CONF" 2>/dev/null || true
    sed -i -E "s|^(\s*ssl_certificate_key\s+).*|\1${PANEL_CERT_KEY};|" "$PANEL_NGINX_CONF" 2>/dev/null || true
fi

# --- FIX v3.3: PATCH PANEL .env untuk reverse proxy HTTPS ---
STEP="05c2 Patch Panel HTTPS"
info "Patch panel .env (APP_URL / TRUSTED_PROXIES / SESSION_SECURE_COOKIE)..."
PANEL_ENV="/var/www/pterodactyl/.env"
if [[ -f "$PANEL_ENV" ]]; then
    if grep -q '^APP_URL=' "$PANEL_ENV"; then
        sed -i "s|^APP_URL=.*|APP_URL=https://${PANEL_DOMAIN}|" "$PANEL_ENV"
    else
        echo "APP_URL=https://${PANEL_DOMAIN}" >> "$PANEL_ENV"
    fi
    if grep -q '^TRUSTED_PROXIES=' "$PANEL_ENV"; then
        sed -i 's|^TRUSTED_PROXIES=.*|TRUSTED_PROXIES=*|' "$PANEL_ENV"
    else
        echo 'TRUSTED_PROXIES=*' >> "$PANEL_ENV"
    fi
    if grep -q '^SESSION_SECURE_COOKIE=' "$PANEL_ENV"; then
        sed -i 's|^SESSION_SECURE_COOKIE=.*|SESSION_SECURE_COOKIE=true|' "$PANEL_ENV"
    else
        echo 'SESSION_SECURE_COOKIE=true' >> "$PANEL_ENV"
    fi
    ok "Panel .env dipatch."
else
    warn "Panel .env tidak ditemukan — lewati patch .env."
fi

# --- FIX v3.3: PATCH NGINX PANEL X-Forwarded-Proto ---
if [[ -f "$PANEL_NGINX_CONF" ]]; then
    if ! grep -q "HTTP_X_FORWARDED_PROTO" "$PANEL_NGINX_CONF"; then
        info "Patch nginx panel: HTTP_X_FORWARDED_PROTO..."
        if grep -q "fastcgi_param SCRIPT_FILENAME" "$PANEL_NGINX_CONF"; then
            sed -i '/fastcgi_param SCRIPT_FILENAME/a\        fastcgi_param HTTP_X_FORWARDED_PROTO $scheme;' "$PANEL_NGINX_CONF"
        elif grep -q "include fastcgi_params;" "$PANEL_NGINX_CONF"; then
            sed -i '/include fastcgi_params;/a\        fastcgi_param HTTP_X_FORWARDED_PROTO $scheme;' "$PANEL_NGINX_CONF"
        fi
        grep -q "HTTP_X_FORWARDED_PROTO" "$PANEL_NGINX_CONF" && ok "nginx dipatch." || warn "Patch nginx gagal."
    else
        ok "nginx sudah punya HTTP_X_FORWARDED_PROTO."
    fi
fi

cd /var/www/pterodactyl
php artisan optimize:clear >/dev/null 2>&1 || true
chown -R www-data:www-data /var/www/pterodactyl
systemctl enable --now nginx mariadb redis-server >/dev/null 2>&1 || true
[[ -f /etc/systemd/system/pteroq.service ]] && systemctl enable --now pteroq 2>/dev/null || true
nginx -t || error_exit 1 "nginx config test gagal"
systemctl reload nginx 2>/dev/null || systemctl restart nginx
php artisan --version || error_exit 1 "php artisan gagal"
systemctl is-active --quiet nginx   || error_exit 1 "Nginx tidak aktif"
systemctl is-active --quiet mariadb || error_exit 1 "MariaDB tidak aktif"
ok "Panel terpasang dan service utama aktif."

# =========================================================================
# 06 WINGS
# =========================================================================
STEP="06 Wings binary"
banner "[06] Install Wings"
if ! command -v docker >/dev/null 2>&1; then
    info "Install Docker..."
    curl -fsSL https://get.docker.com | sh || error_exit 1 "Gagal install Docker"
fi
systemctl enable docker.socket docker >/dev/null 2>&1 || true
systemctl start docker.socket 2>/dev/null || true
systemctl start docker 2>/dev/null || true
if ! docker info >/dev/null 2>&1; then
    warn "Docker belum jalan — fallback iptables legacy..."
    apt-get install -y -qq iptables >/dev/null 2>&1 || true
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
    systemctl reset-failed docker 2>/dev/null || true
    systemctl restart docker 2>/dev/null || true
    sleep 2
fi
docker info >/dev/null 2>&1 && ok "Docker aktif." || warn "Docker masih bermasalah — dicek ulang di step 13."

if [[ -x /usr/local/bin/wings ]]; then
    warn "Wings binary sudah ada — skip download"
else
    info "Download wings binary..."
    ARCH_W="amd64"
    case "$(uname -m)" in aarch64|arm64) ARCH_W="arm64" ;; esac
    curl -fsSL "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH_W}" \
        -o /usr/local/bin/wings || error_exit 1 "Gagal download wings binary"
fi
chmod +x /usr/local/bin/wings
[[ -x /usr/local/bin/wings ]] || error_exit 1 "Wings binary tidak tersedia"
ok "Wings binary siap."

# =========================================================================
# 07 API KEYS
# =========================================================================
STEP="07 API Keys"
banner "[07] Membuat PLTA / PLTC"
cat > "$WORK_DIR/create_keys.php" <<'PHP'
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();
$user = \Pterodactyl\Models\User::where('root_admin', 1)->first();
if (!$user) { fwrite(STDERR, "NO_ADMIN\n"); exit(1); }
$service = app(\Pterodactyl\Services\Api\KeyCreationService::class);
$appKey = $service->setKeyType(\Pterodactyl\Models\ApiKey::TYPE_APPLICATION)->handle(
    ['user_id' => $user->id, 'memo' => 'RAFZHOST Auto PLTA', 'allowed_ips' => []],
    ['r_locations'=>3,'r_nodes'=>3,'r_allocations'=>3,'r_nests'=>3,'r_eggs'=>3,'r_servers'=>3,'r_users'=>3,'r_database_hosts'=>3,'r_server_databases'=>3]
);
$accountKey = $service->setKeyType(\Pterodactyl\Models\ApiKey::TYPE_ACCOUNT)->handle(
    ['user_id' => $user->id, 'memo' => 'RAFZHOST Auto PLTC', 'allowed_ips' => []]
);
echo "ADMIN_ID={$user->id}\n";
echo 'PLTA=' . $appKey->identifier . decrypt($appKey->token) . "\n";
echo 'PLTC=' . $accountKey->identifier . decrypt($accountKey->token) . "\n";
PHP
KEY_OUTPUT="$(cd /var/www/pterodactyl && php "$WORK_DIR/create_keys.php" 2>&1)" || error_exit 1 "Gagal membuat API key (PLTA/PLTC)"
echo "$KEY_OUTPUT"
PLTA="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^PLTA=//p' | head -1)"
PLTC="$(printf '%s\n' "$KEY_OUTPUT" | sed -n 's/^PLTC=//p' | head -1)"
[[ "$PLTA" == ptla_* ]] || error_exit 1 "PLTA gagal dibuat / format salah"
[[ "$PLTC" == ptlc_* ]] && ok "PLTC berhasil dibuat."
ok "PLTA berhasil dibuat."

# =========================================================================
# 08-11 API
# =========================================================================
STEP="08 Application API"
banner "[08] Menyiapkan Application API"
API_BASE="https://$PANEL_DOMAIN/api/application"
API_HEADERS=(-H "Authorization: Bearer $PLTA" -H "Accept: Application/vnd.pterodactyl.v1+json" -H "Content-Type: application/json")

api_req() {
    local method="$1" url="$2" data="${3:-}" out rc=0
    if [[ -n "$data" ]]; then
        out="$(curl -fsSk --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 90 \
            "${API_HEADERS[@]}" -X "$method" -d "$data" "$url" 2>&1)" || rc=$?
    else
        out="$(curl -fsSk --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 90 \
            "${API_HEADERS[@]}" -X "$method" "$url" 2>&1)" || rc=$?
    fi
    if [[ $rc -ne 0 ]]; then echo "$out" >&2; return $rc; fi
    printf '%s' "$out"
}
api_error() { echo "$1" | jq -r '.errors[]?.detail // .message // empty' 2>/dev/null | paste -sd ' | ' - || echo "$1"; }

LOCATIONS_JSON="$(api_req GET "$API_BASE/locations?per_page=100")" || error_exit 1 "PLTA tidak bisa mengakses Application API"
ok "Application API dapat diakses."

STEP="09 Location"
banner "[09] Membuat Location"
LOCATION_ID="$(printf '%s' "$LOCATIONS_JSON" | jq -r --arg s "$LOCATION_SHORT" '.data[] | select(.attributes.short == $s) | .attributes.id' | head -1)"
if [[ -n "$LOCATION_ID" && "$LOCATION_ID" != "null" ]]; then
    ok "Location sudah ada. ID: $LOCATION_ID"
else
    LOC_RAW="$(api_req POST "$API_BASE/locations" "$(jq -nc --arg s "$LOCATION_SHORT" --arg l "$LOCATION_LONG" '{short:$s,long:$l}')" 2>&1)" || true
    LOCATION_ID="$(printf '%s' "$LOC_RAW" | jq -r '.attributes.id // .data.attributes.id // empty' 2>/dev/null)"
    if [[ -z "$LOCATION_ID" || "$LOCATION_ID" == "null" ]]; then
        LOCATIONS_JSON="$(api_req GET "$API_BASE/locations?per_page=100" 2>/dev/null || true)"
        LOCATION_ID="$(printf '%s' "$LOCATIONS_JSON" | jq -r --arg s "$LOCATION_SHORT" '.data[] | select(.attributes.short == $s) | .attributes.id' | head -1)"
    fi
    [[ -n "$LOCATION_ID" && "$LOCATION_ID" != "null" ]] || error_exit 1 "Gagal membuat Location"
    ok "Location siap. ID: $LOCATION_ID"
fi

STEP="10 Node"
banner "[10] Membuat Node"
NODES_JSON="$(api_req GET "$API_BASE/nodes?per_page=100")" || error_exit 1 "Gagal ambil list nodes"
NODE_ID="$(printf '%s' "$NODES_JSON" | jq -r --arg f "$NODE_DOMAIN" '.data[] | select(.attributes.fqdn == $f) | .attributes.id' | head -1)"
RAM_MB="$(free -m | awk 'NR==2{print $2}')"
DISK_MB="$(df -BM / | awk 'NR==2{gsub(/M/,""); print $4}')"
(( RAM_MB > 512 )) && RAM_MB=$((RAM_MB - 512))
(( DISK_MB > 3072 )) && DISK_MB=$((DISK_MB - 3072))

node_payload() {
    jq -nc --arg name "$NODE_NAME" --arg desc "$NODE_DESCRIPTION" --argjson loc "$LOCATION_ID" \
        --arg fqdn "$NODE_DOMAIN" --argjson mem "$RAM_MB" --argjson disk "$DISK_MB" \
        --argjson up "$UPLOAD_SIZE" --argjson sftp "$SFTP_PORT" --argjson listen "$DAEMON_PORT" \
        --argjson mo "$MEMORY_OVERALLOCATE" --argjson do "$DISK_OVERALLOCATE" \
        '{name:$name,description:$desc,location_id:$loc,fqdn:$fqdn,scheme:"https",behind_proxy:false,
          public:true,daemon_base:"/var/lib/pterodactyl/volumes",memory:$mem,memory_overallocate:$mo,
          disk:$disk,disk_overallocate:$do,upload_size:$up,daemon_sftp:$sftp,daemon_listen:$listen,
          maintenance_mode:false}'
}

if [[ -n "$NODE_ID" && "$NODE_ID" != "null" ]]; then
    ok "Node sudah ada. ID: $NODE_ID"
    api_req PATCH "$API_BASE/nodes/$NODE_ID" "$(node_payload)" >/dev/null 2>&1 || true
else
    NODE_RAW="$(api_req POST "$API_BASE/nodes" "$(node_payload)" 2>&1)" || true
    NODE_ID="$(printf '%s' "$NODE_RAW" | jq -r '.attributes.id // .data.attributes.id // empty' 2>/dev/null)"
    if [[ -z "$NODE_ID" || "$NODE_ID" == "null" ]]; then
        NODES_JSON="$(api_req GET "$API_BASE/nodes?per_page=100" 2>/dev/null || true)"
        NODE_ID="$(printf '%s' "$NODES_JSON" | jq -r --arg f "$NODE_DOMAIN" '.data[] | select(.attributes.fqdn == $f) | .attributes.id' | head -1)"
    fi
    [[ -n "$NODE_ID" && "$NODE_ID" != "null" ]] || error_exit 1 "Gagal membuat Node"
    ok "Node berhasil dibuat. ID: $NODE_ID"
fi

STEP="11 Allocation"
banner "[11] Membuat Allocation"
ALLOC_JSON="$(api_req GET "$API_BASE/nodes/$NODE_ID/allocations?per_page=100")" || error_exit 1 "Gagal ambil allocation"
EXISTING_PORT="$(printf '%s' "$ALLOC_JSON" | jq -r --arg ip "$ALLOC_IP" --argjson p "$ALLOCATION_START" \
    '.data[] | select(.attributes.ip == $ip and .attributes.port == $p) | .attributes.port' | head -1)"
if [[ "$EXISTING_PORT" == "$ALLOCATION_START" ]]; then
    ok "Allocation $ALLOC_IP:$ALLOCATION_START sudah ada."
else
    ALLOC_RAW="$(api_req POST "$API_BASE/nodes/$NODE_ID/allocations" \
        "$(jq -nc --arg ip "$ALLOC_IP" --arg alias "$ALLOC_ALIAS" --arg ports "$ALLOCATION_START-$ALLOCATION_END" '{ip:$ip,alias:$alias,ports:[$ports]}')" 2>&1)" \
        || error_exit 1 "Gagal membuat Allocation: $(api_error "$ALLOC_RAW")"
    ok "Allocation berhasil dibuat."
fi

# =========================================================================
# 12 WINGS CONFIG — pakai unified cert dari step 05c
# =========================================================================
STEP="12 Wings config"
banner "[12] Menulis konfigurasi Wings (native :$DAEMON_PORT + TLS)"
CONFIG_YML="/etc/pterodactyl/config.yml"
mkdir -p /etc/pterodactyl

# NODE_CERT_PEM / NODE_CERT_KEY sudah di-set di step 05c
[[ -f "$NODE_CERT_PEM" && -f "$NODE_CERT_KEY" ]] || error_exit 1 "Cert node tidak ditemukan: $NODE_CERT_PEM"

cat > "$WORK_DIR/node-config.raw" <<EOFCFG
debug: false
uuid: $(cat /proc/sys/kernel/random/uuid)
token_id: PLACEHOLDER_TOKEN_ID
token: PLACEHOLDER_TOKEN
api:
  host: 0.0.0.0
  port: ${DAEMON_PORT}
  ssl:
    enabled: true
    cert: ${NODE_CERT_PEM}
    key: ${NODE_CERT_KEY}
  upload_limit: ${UPLOAD_SIZE}
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind_port: ${SFTP_PORT}
allowed_mounts: []
remote: https://${PANEL_DOMAIN}
EOFCFG

UUID_DB="$(mariadb -u root panel -N -e "SELECT uuid FROM nodes WHERE id=$NODE_ID;" 2>/dev/null || true)"
TOKEN_ID_DB="$(mariadb -u root panel -N -e "SELECT daemon_token_id FROM nodes WHERE id=$NODE_ID;" 2>/dev/null || true)"
TOKEN_DB_ENC="$(mariadb -u root panel -N -e "SELECT daemon_token FROM nodes WHERE id=$NODE_ID;" 2>/dev/null || true)"
[[ -n "$UUID_DB" && -n "$TOKEN_ID_DB" && -n "$TOKEN_DB_ENC" ]] || error_exit 1 "Gagal baca node token dari DB panel"

cat > "$WORK_DIR/decrypt_token.php" <<'PHP'
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
echo decrypt(getenv('ENC_TOKEN')), "\n";
PHP
TOKEN_PLAIN="$(cd /var/www/pterodactyl && ENC_TOKEN="$TOKEN_DB_ENC" php "$WORK_DIR/decrypt_token.php" 2>/dev/null | tail -1)"
[[ -n "$TOKEN_PLAIN" ]] || error_exit 1 "Gagal decrypt daemon token node"
sed -i "s|PLACEHOLDER_TOKEN_ID|${TOKEN_ID_DB}|; s|PLACEHOLDER_TOKEN|${TOKEN_PLAIN}|" "$WORK_DIR/node-config.raw"

if [[ -n "$UUID_DB" ]]; then
    sed -i "s|^uuid: .*|uuid: ${UUID_DB}|" "$WORK_DIR/node-config.raw"
fi

python3 - "$WORK_DIR/node-config.raw" "$CONFIG_YML" <<'PYC'
import sys
src, dest = sys.argv[1], sys.argv[2]
lines = []
for line in open(src):
    line = line.rstrip('\n')
    if line.startswith('token: ') and len(line) > 7:
        lines.append(f"token: '{line[7:]}'")
    else:
        lines.append(line)
open(dest, 'w').write('\n'.join(lines) + '\n')
PYC
printf 'trusted_proxies:\n- 127.0.0.1\n- ::1\n' >> "$CONFIG_YML"
printf 'allowed_origins:\n- https://%s\n' "$PANEL_DOMAIN" >> "$CONFIG_YML"
chmod 600 "$CONFIG_YML"; chown root:root "$CONFIG_YML"
ok "config.yml ditulis (native :$DAEMON_PORT, TLS: $NODE_CERT_PEM)."

# =========================================================================
# 13 START WINGS
# =========================================================================
STEP="13 Start Wings"
banner "[13] Menjalankan Wings"
cat > /etc/systemd/system/wings.service <<'WINGSEOF'
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
systemctl daemon-reload
systemctl enable wings >/dev/null 2>&1 || true
systemctl restart wings || error_exit 1 "Gagal start wings"
sleep 4
systemctl is-active --quiet wings || { journalctl -u wings -n 40 --no-pager || true; error_exit 1 "Wings gagal start"; }
ok "Wings aktif."

if [[ -f /var/www/pterodactyl/.env ]]; then
    sed -i '/^GUZZLE_TIMEOUT=/d; /^GUZZLE_CONNECT_TIMEOUT=/d' /var/www/pterodactyl/.env
    echo 'GUZZLE_TIMEOUT=900' >> /var/www/pterodactyl/.env
    echo 'GUZZLE_CONNECT_TIMEOUT=60' >> /var/www/pterodactyl/.env
fi

# =========================================================================
# 14 VERIFIKASI PANEL <-> WINGS
# =========================================================================
STEP="14 Verifikasi"
banner "[14] Verifikasi Panel <-> Wings"
if ! ufw status 2>/dev/null | grep -q "$DAEMON_PORT"; then
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "$DAEMON_PORT" >/dev/null 2>&1 || true
        ufw allow "$SFTP_PORT" >/dev/null 2>&1 || true
    fi
fi
cat > "$WORK_DIR/verify_wings.php" <<PHP
<?php
require '/var/www/pterodactyl/vendor/autoload.php';
\$app = require_once '/var/www/pterodactyl/bootstrap/app.php';
\$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
try {
    \$info = app(Pterodactyl\Repositories\Wings\DaemonConfigurationRepository::class)
        ->setNode(Pterodactyl\Models\Node::find(${NODE_ID}))
        ->getSystemInformation();
    echo 'WINGS_OK version=' . (\$info['version'] ?? 'unknown') . "\n";
} catch (Throwable \$e) {
    fwrite(STDERR, 'WINGS_FAIL: ' . \$e->getMessage() . "\n");
    exit(1);
}
PHP
VERIFY_RC=0
VERIFY_OUT="$(cd /var/www/pterodactyl && php "$WORK_DIR/verify_wings.php" 2>&1)" || VERIFY_RC=$?
echo "$VERIFY_OUT"
if [[ $VERIFY_RC -ne 0 ]]; then
    warn "Panel belum bisa akses wings — restart & retry sekali..."
    systemctl restart wings; sleep 5
    VERIFY_OUT="$(cd /var/www/pterodactyl && php "$WORK_DIR/verify_wings.php" 2>&1)" || VERIFY_RC=$?
    echo "$VERIFY_OUT"
    [[ $VERIFY_RC -eq 0 ]] || error_exit 1 "Panel gagal mengakses Wings: $VERIFY_OUT"
fi
ok "Panel berhasil mengakses Wings."

NODE_CODE="$(curl -ksS --max-time 15 -o /dev/null -w '%{http_code}' "https://$NODE_DOMAIN:$DAEMON_PORT/api/system" 2>/dev/null || echo 000)"
if [[ "$NODE_CODE" == "401" || "$NODE_CODE" == "403" || "$NODE_CODE" == "200" ]]; then
    ok "Node reachable via https://$NODE_DOMAIN:$DAEMON_PORT (code: $NODE_CODE)."
else
    warn "Node tidak reachable dari server ini (code: $NODE_CODE) — cek cloud firewall."
fi

# =========================================================================
# 15 IMPORT EGG
# =========================================================================
STEP="15 Egg"
banner "[15] Import Egg — Nusantara Ultimate v9 (secured)"
info "Menulis egg (in-memory + temp terkunci)..."
EGG_B64="eyJfY29tbWVudCI6IkRPIE5PVCBFRElUOiBGSUxFIEdFTkVSQVRFRCBBVVRPTUFUSUNBTExZIEJZIFBURVJPREFDVFlMIFBBTkVMIC0gUFRFUk9EQUNUWUwuSU8iLCJtZXRhIjp7InZlcnNpb24iOiJQVERMX3YyIiwidXBkYXRlX3VybCI6bnVsbH0sImV4cG9ydGVkX2F0IjoiMjAyNi0xMC0wMlQwMTowMDowMCswNzowMCIsIm5hbWUiOiJOdXNhbnRhcmEgVWx0aW1hdGUgLSBQTTIgTXVsdGktQm90ICsgU1NIICsgWWFybi9OUE0gKyBQeXRob24gKyBDRiB2OSIsImF1dGhvciI6InJhZnpob3N0QHJhZnpob3N0Lm15LmlkIiwiZGVzY3JpcHRpb24iOiJFZ2cgc3RhYmlsLiBQTTIgbXVsdGktYm90ICsgU1NIIChkZWZhdWx0IE9GRikuIEZ1bGwgd2FybmEgKyBhbmltYXNpIGRpIHNlbXVhIFVJLiBTU0ggaW5mbyB0ZXRhcCBtdW5jdWwgZGkgUE0yIFVJIHNldGVsYWggY2xlYXIuIEF1dG8tcmVnZW5lcmF0ZS4gQW50aSBjcmFzaC4iLCJmZWF0dXJlcyI6W10sImRvY2tlcl9pbWFnZXMiOnsiTm9kZUpTIDI0IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzI0IiwiTm9kZUpTIDIzIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzIzIiwiTm9kZUpTIDIyIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzIyIiwiTm9kZUpTIDIxIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzIxIiwiTm9kZUpTIDIwIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzIwIiwiTm9kZUpTIDE5IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzE5IiwiTm9kZUpTIDE4IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzE4IiwiTm9kZUpTIDE3IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzE3IiwiTm9kZUpTIDE2IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzE2IiwiTm9kZUpTIDE1IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6bm9kZWpzXzE1IiwiUHl0aG9uIDMuMTIiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpweXRob25fMy4xMiIsIlB5dGhvbiAzLjExIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6cHl0aG9uXzMuMTEiLCJQeXRob24gMy4xMCI6ImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnB5dGhvbl8zLjEwIiwiUHl0aG9uIDMuOSI6ImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnB5dGhvbl8zLjkiLCJQeXRob24gMy44IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6cHl0aG9uXzMuOCIsIkRlYmlhbiBPUyAoVW5pdmVyc2FsKSI6ImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOmRlYmlhbiIsIlVidW50dSBPUyAoVW5pdmVyc2FsKSI6ImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnVidW50dSJ9LCJmaWxlX2RlbnlsaXN0IjpbXSwic3RhcnR1cCI6InNldCArZTsgZXhwb3J0IEhPTUU9L2hvbWUvY29udGFpbmVyOyBleHBvcnQgUE0yX0hPTUU9L2hvbWUvY29udGFpbmVyLy5wbTI7IGV4cG9ydCBOT0RFX1BBVEg9L2hvbWUvY29udGFpbmVyLy5kZXBzL25vZGVfbW9kdWxlczsgZXhwb3J0IFBBVEg9XCIvaG9tZS9jb250YWluZXIvLmRlcHMvbm9kZV9tb2R1bGVzLy5iaW46L3Vzci9sb2NhbC9iaW46L3Vzci9iaW46L2JpbjovdXNyL3NiaW46L3NiaW5cIjsgbWtkaXIgLXAgL2hvbWUvY29udGFpbmVyLy5kZXBzIC9ob21lL2NvbnRhaW5lci8ucG0yOyBjZCAvaG9tZS9jb250YWluZXI7IGlmIFsgLWQgLmdpdCBdICYmIFsgXCIke0FVVE9fVVBEQVRFfVwiID0gXCIxXCIgXTsgdGhlbiBnaXQgcHVsbCA+L2Rldi9udWxsIDI+JjEgfHwgdHJ1ZTsgZmk7IGlmIFsgLW4gXCIke0NMT1VERkxBUkVEX1RPS0VOfVwiIF07IHRoZW4gd2dldCAtcSBodHRwczovL2dpdGh1Yi5jb20vY2xvdWRmbGFyZS9jbG91ZGZsYXJlZC9yZWxlYXNlcy9sYXRlc3QvZG93bmxvYWQvY2xvdWRmbGFyZWQtbGludXgtYW1kNjQgLU8gL2hvbWUvY29udGFpbmVyL2Nsb3VkZmxhcmVkIDI+L2Rldi9udWxsICYmIGNobW9kICt4IC9ob21lL2NvbnRhaW5lci9jbG91ZGZsYXJlZCAmJiAvaG9tZS9jb250YWluZXIvY2xvdWRmbGFyZWQgdHVubmVsIC0tbm8tYXV0b3VwZGF0ZSBydW4gLS10b2tlbiBcIiR7Q0xPVURGTEFSRURfVE9LRU59XCIgPi9kZXYvbnVsbCAyPiYxICYgZmk7IHJlcV9maWxlPVwiJHtSRVFVSVJFTUVOVFNfRklMRTotcmVxdWlyZW1lbnRzLnR4dH1cIjsgaWYgWyAtZiBcIi9ob21lL2NvbnRhaW5lci8ke3JlcV9maWxlfVwiIF07IHRoZW4gcGlwMyBpbnN0YWxsIC1yIFwiL2hvbWUvY29udGFpbmVyLyR7cmVxX2ZpbGV9XCIgLS1icmVhay1zeXN0ZW0tcGFja2FnZXMgPi9kZXYvbnVsbCAyPiYxIHx8IHBpcCBpbnN0YWxsIC1yIFwiL2hvbWUvY29udGFpbmVyLyR7cmVxX2ZpbGV9XCIgPi9kZXYvbnVsbCAyPiYxIHx8IHRydWU7IGZpOyBpZiBbIC1mIC9ob21lL2NvbnRhaW5lci9wYWNrYWdlLmpzb24gXTsgdGhlbiBpZiBbIFwiJHtQQUNLQUdFX01BTkFHRVJ9XCIgPSBcIm5wbVwiIF07IHRoZW4geWVzIFwiXCIgfCBucG0gaW5zdGFsbCAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXQgPi9kZXYvbnVsbCAyPiYxIHx8IHRydWU7IGVsc2UgY29tbWFuZCAtdiB5YXJuID4vZGV2L251bGwgMj4mMSB8fCBucG0gaW5zdGFsbCAtZyB5YXJuIC0tc2lsZW50ID4vZGV2L251bGwgMj4mMSB8fCB0cnVlOyB5ZXMgfCB5YXJuIGluc3RhbGwgLS1ub24taW50ZXJhY3RpdmUgLS1pZ25vcmUtZW5naW5lcyA+L2Rldi9udWxsIDI+JjEgfHwgdHJ1ZTsgZmk7IHJtIC1yZiAubnBtIC5sb2cgLmNhY2hlIC55YXJuLWNhY2hlIDI+L2Rldi9udWxsIHx8IHRydWU7IGZpOyBpZiBbICEgLWQgL2hvbWUvY29udGFpbmVyLy5kZXBzL25vZGVfbW9kdWxlcy9wbTIgXSB8fCBbICEgLWQgL2hvbWUvY29udGFpbmVyLy5kZXBzL25vZGVfbW9kdWxlcy9zc2gyIF07IHRoZW4gY2QgL2hvbWUvY29udGFpbmVyLy5kZXBzOyBbIC1mIHBhY2thZ2UuanNvbiBdIHx8IGVjaG8gJ3tcIm5hbWVcIjpcImRlcHNcIixcInZlcnNpb25cIjpcIjEuMC4wXCIsXCJwcml2YXRlXCI6dHJ1ZX0nID4gcGFja2FnZS5qc29uOyBucG0gaW5zdGFsbCBwbTIgc3NoMiAtLW5vLWZ1bmQgLS1uby1hdWRpdCAtLWxvZ2xldmVsPWVycm9yID4vZGV2L251bGwgMj4mMSB8fCB0cnVlOyBjZCAvaG9tZS9jb250YWluZXI7IGZpOyBpZiBbICEgLWYgL2hvbWUvY29udGFpbmVyLy5kZXBzL3NzaC1zZXJ2ZXIuanMgXTsgdGhlbiBwcmludGYgJyVzJyAnSXlFdmRYTnlMMkpwYmk5bGJuWWdibTlrWlFvbmRYTmxJSE4wY21samRDYzdDbU52Ym5OMElIc2dVMlZ5ZG1WeUlIMGdQU0J5WlhGMWFYSmxLQ2R6YzJneUp5azdDbU52Ym5OMElIc2djbVZoWkVacGJHVlRlVzVqTENCM2NtbDBaVVpwYkdWVGVXNWpMQ0JsZUdsemRITlRlVzVqSUgwZ1BTQnlaWEYxYVhKbEtDZG1jeWNwT3dwamIyNXpkQ0I3SUdkbGJtVnlZWFJsUzJWNVVHRnBjbE41Ym1NZ2ZTQTlJSEpsY1hWcGNtVW9KMk55ZVhCMGJ5Y3BPd3BqYjI1emRDQjdJR1Y0WldNc0lHVjRaV05UZVc1aklIMGdQU0J5WlhGMWFYSmxLQ2RqYUdsc1pGOXdjbTlqWlhOekp5azdDbU52Ym5OMElHOXpJRDBnY21WeGRXbHlaU2duYjNNbktUc0tZMjl1YzNRZ1VFOVNWQ0E5SUhCaGNuTmxTVzUwS0hCeWIyTmxjM011Wlc1MkxsTkZVbFpGVWw5UVQxSlVJSHg4SUhCeWIyTmxjM011Wlc1MkxsTlRTRjlRVDFKVUlIeDhJQ2N5TURBeEp5d2dNVEFwT3dwamIyNXpkQ0JNVDBkSlRsOVZVMFZTSUQwZ2NISnZZMlZ6Y3k1bGJuWXVVMU5JWDFWVFJWSWdmSHdnSjNKdmIzUW5Pd3BqYjI1emRDQkVTVk5RVEVGWlgxVlRSVklnUFNCd2NtOWpaWE56TG1WdWRpNVRVMGhmUkVsVFVFeEJXVjlWVTBWU0lIeDhJQ2R6YzJnbk93cG1kVzVqZEdsdmJpQm5aWFJRWVhOemQyOXlaQ2dwSUhzS0lDQnBaaUFvY0hKdlkyVnpjeTVsYm5ZdVUxTklYMUJCVTFOWFQxSkVLU0J5WlhSMWNtNGdjSEp2WTJWemN5NWxibll1VTFOSVgxQkJVMU5YVDFKRU93b2dJR052Ym5OMElIQm1JRDBnSnk5b2IyMWxMMk52Ym5SaGFXNWxjaTh1YzNOb0xYQmhjM04zYjNKa0p6c0tJQ0IwY25rZ2V5QnBaaUFvWlhocGMzUnpVM2x1WXlod1ppa3BJSEpsZEhWeWJpQnlaV0ZrUm1sc1pWTjVibU1vY0dZc0lDZDFkR1k0SnlrdWRISnBiU2dwT3lCOUlHTmhkR05vSUNobEtTQjdmUW9nSUhKbGRIVnliaUFuWTJoaGJtZGxiV1VuT3dwOUNtTnZibk4wSUZCQlUxTlhUMUpFSUQwZ1oyVjBVR0Z6YzNkdmNtUW9LVHNLWm5WdVkzUnBiMjRnWjJWMFJHbHpjR3hoZVVodmMzUW9LU0I3Q2lBZ1kyOXVjM1FnWXlBOUlGdHdjbTlqWlhOekxtVnVkaTVRWDFORlVsWkZVbDlPUVUxRkxDQndjbTlqWlhOekxtVnVkaTVUUlZKV1JWSmZUa0ZOUlYwN0NpQWdabTl5SUNoamIyNXpkQ0I0SUc5bUlHTXBJR2xtSUNoNElDWW1JSGd1ZEhKcGJTZ3BLU0J5WlhSMWNtNGdlQzUwY21sdEtDazdDaUFnZEhKNUlIc2dZMjl1YzNRZ2FDQTlJRzl6TG1odmMzUnVZVzFsS0NrN0lHbG1JQ2hvS1NCeVpYUjFjbTRnYURzZ2ZTQmpZWFJqYUNBb1pTa2dlMzBLSUNCcFppQW9jSEp2WTJWemN5NWxibll1VUY5VFJWSldSVkpmVlZWSlJDa2djbVYwZFhKdUlIQnliMk5sYzNNdVpXNTJMbEJmVTBWU1ZrVlNYMVZWU1VRdWMyeHBZMlVvTUN3Z09DazdDaUFnY21WMGRYSnVJQ2RqYjI1MFlXbHVaWEluT3dwOUNtTnZibk4wSUVSSlUxQk1RVmxmU0U5VFZDQTlJR2RsZEVScGMzQnNZWGxJYjNOMEtDazdDbVoxYm1OMGFXOXVJR2RsZEZCMVlteHBZMGh2YzNRb0tTQjdDaUFnZEhKNUlIc0tJQ0FnSUdOdmJuTjBJR2x3SUQwZ1pYaGxZMU41Ym1Nb0oyTjFjbXdnTFhNZ0xXMGdOU0JwWm1OdmJtWnBaeTV0WlNBeVBpOWtaWFl2Ym5Wc2JDY3NJSHNnWlc1amIyUnBibWM2SUNkMWRHWTRKeXdnZEdsdFpXOTFkRG9nT0RBd01DQjlLUzUwY21sdEtDazdDaUFnSUNCcFppQW9hWEFnSmlZZ0wxNWJNQzA1WVMxbVFTMUdManBkS3lRdkxuUmxjM1FvYVhBcEtTQnlaWFIxY200Z2FYQTdDaUFnZlNCallYUmphQ0FvWlNrZ2UzMEtJQ0IwY25rZ2V3b2dJQ0FnWTI5dWMzUWdibVYwY3lBOUlHOXpMbTVsZEhkdmNtdEpiblJsY21aaFkyVnpLQ2s3Q2lBZ0lDQm1iM0lnS0dOdmJuTjBJRzVoYldVZ2IyWWdUMkpxWldOMExtdGxlWE1vYm1WMGN5a3BJSHNLSUNBZ0lDQWdabTl5SUNoamIyNXpkQ0J1WlhRZ2IyWWdibVYwYzF0dVlXMWxYU2tnZXdvZ0lDQWdJQ0FnSUdsbUlDaHVaWFF1Wm1GdGFXeDVJRDA5UFNBblNWQjJOQ2NnSmlZZ0lXNWxkQzVwYm5SbGNtNWhiQ2tnY21WMGRYSnVJRzVsZEM1aFpHUnlaWE56T3dvZ0lDQWdJQ0I5Q2lBZ0lDQjlDaUFnZlNCallYUmphQ0FvWlNrZ2UzMEtJQ0J5WlhSMWNtNGdKMnh2WTJGc2FHOXpkQ2M3Q24wS1kyOXVjM1FnUXlBOUlIc0tJQ0J5WlhObGREb25YSGd4WWxzd2JTY3NJR0p2YkdRNkoxeDRNV0piTVcwbkxDQmthVzA2SjF4NE1XSmJNbTBuTEFvZ0lISmxaRG9uWEhneFlsc3pNVzBuTENCbmNtVmxiam9uWEhneFlsc3pNbTBuTENCNVpXeHNiM2M2SjF4NE1XSmJNek50Snl3S0lDQmliSFZsT2lkY2VERmlXek0wYlNjc0lHMWhaMlZ1ZEdFNkoxeDRNV0piTXpWdEp5d2dZM2xoYmpvblhIZ3hZbHN6Tm0wbkxBb2dJSGRvYVhSbE9pZGNlREZpV3pNM2JTY3NJR2R5WVhrNkoxeDRNV0piT1RCdEp5d0tJQ0JpVW1Wa09pZGNlREZpV3preGJTY3NJR0pIY21WbGJqb25YSGd4WWxzNU1tMG5MQ0JpV1dWc2JHOTNPaWRjZURGaVd6a3piU2NzSUdKRGVXRnVPaWRjZURGaVd6azJiU2NLZlRzS1kyOXVjM1FnUVV4TVQwTmZUVVZOWDAxQ0lEMGdjR0Z5YzJWSmJuUW9jSEp2WTJWemN5NWxibll1VTBWU1ZrVlNYMDFGVFU5U1dTQjhmQ0FuTUNjc0lERXdLVHNLWTI5dWMzUWdRVXhNVDBOZlExQlZYMUJEVkNBOUlIQmhjbk5sU1c1MEtIQnliMk5sYzNNdVpXNTJMbE5GVWxaRlVsOURVRlVnZkh3Z0p6QW5MQ0F4TUNrN0NtWjFibU4wYVc5dUlHWnZjbTFoZEVKNWRHVnpLR0o1ZEdWektTQjdDaUFnYVdZZ0tDRmllWFJsY3lCOGZDQmllWFJsY3lBOFBTQXdLU0J5WlhSMWNtNGdKekFnUWljN0NpQWdZMjl1YzNRZ2F5QTlJREV3TWpRN0NpQWdZMjl1YzNRZ2MybDZaWE1nUFNCYkowSW5MQ2RMUWljc0owMUNKeXduUjBJbkxDZFVRaWRkT3dvZ0lHTnZibk4wSUdrZ1BTQk5ZWFJvTG1ac2IyOXlLRTFoZEdndWJHOW5LR0o1ZEdWektTQXZJRTFoZEdndWJHOW5LR3NwS1RzS0lDQnlaWFIxY200Z0tHSjVkR1Z6SUM4Z1RXRjBhQzV3YjNjb2F5d2dhU2twTG5SdlJtbDRaV1FvTVNrZ0t5QW5JQ2NnS3lCemFYcGxjMXRwWFRzS2ZRcG1kVzVqZEdsdmJpQnRZV3RsUW1GeUtISmhkR2x2TENCM2FXUjBhQ2tnZXdvZ0lIZHBaSFJvSUQwZ2QybGtkR2dnZkh3Z01qQTdDaUFnY21GMGFXOGdQU0JOWVhSb0xtMWhlQ2d3TENCTllYUm9MbTFwYmlneExDQnlZWFJwYnlrcE93b2dJR052Ym5OMElHWnBiR3hsWkNBOUlFMWhkR2d1Y205MWJtUW9jbUYwYVc4Z0tpQjNhV1IwYUNrN0NpQWdZMjl1YzNRZ1pXMXdkSGtnUFNCM2FXUjBhQ0F0SUdacGJHeGxaRHNLSUNCc1pYUWdZMjlzYjNJZ1BTQkRMbUpIY21WbGJqc0tJQ0JwWmlBb2NtRjBhVzhnUGlBd0xqZ3dLU0JqYjJ4dmNpQTlJRU11WWxKbFpEc0tJQ0JsYkhObElHbG1JQ2h5WVhScGJ5QStJREF1TlRVcElHTnZiRzl5SUQwZ1F5NWlXV1ZzYkc5M093b2dJSEpsZEhWeWJpQmpiMnh2Y2lBcklDZGNkVEkxT0RnbkxuSmxjR1ZoZENobWFXeHNaV1FwSUNzZ1F5NW5jbUY1SUNzZ0oxeDFNalU1TVNjdWNtVndaV0YwS0dWdGNIUjVLU0FySUVNdWNtVnpaWFE3Q24wS1puVnVZM1JwYjI0Z1oyVjBTVzVtYnlncElIc0tJQ0JqYjI1emRDQnNhVzVsY3lBOUlGdGRPd29nSUd4bGRDQnZjMDVoYldVZ1BTQW5WVzVyYm05M2JpYzdDaUFnZEhKNUlIc0tJQ0FnSUdOdmJuTjBJRzl6VW1Wc1pXRnpaU0E5SUhKbFlXUkdhV3hsVTNsdVl5Z25MMlYwWXk5dmN5MXlaV3hsWVhObEp5d2dKM1YwWmpnbktUc0tJQ0FnSUdOdmJuTjBJRzBnUFNCdmMxSmxiR1ZoYzJVdWJXRjBZMmdvTDFCU1JWUlVXVjlPUVUxRlBTSW9MaXNwSWk4cE93b2dJQ0FnYVdZZ0tHMHBJRzl6VG1GdFpTQTlJRzFiTVYwN0NpQWdmU0JqWVhSamFDQW9aU2tnZXlCdmMwNWhiV1VnUFNCdmN5NTBlWEJsS0NrZ0t5QW5JQ2NnS3lCdmN5NXlaV3hsWVhObEtDazdJSDBLSUNCamIyNXpkQ0JyWlhKdVpXd2dQU0J2Y3k1MGVYQmxLQ2tnS3lBbklDY2dLeUJ2Y3k1eVpXeGxZWE5sS0NrN0NpQWdZMjl1YzNRZ2RYQjBhVzFsVTJWaklEMGdUV0YwYUM1bWJHOXZjaWh2Y3k1MWNIUnBiV1VvS1NrN0NpQWdZMjl1YzNRZ1pDQTlJRTFoZEdndVpteHZiM0lvZFhCMGFXMWxVMlZqSUM4Z09EWTBNREFwT3dvZ0lHTnZibk4wSUdnZ1BTQk5ZWFJvTG1ac2IyOXlLQ2gxY0hScGJXVlRaV01nSlNBNE5qUXdNQ2tnTHlBek5qQXdLVHNLSUNCamIyNXpkQ0J0YVNBOUlFMWhkR2d1Wm14dmIzSW9LSFZ3ZEdsdFpWTmxZeUFsSURNMk1EQXBJQzhnTmpBcE93b2dJR052Ym5OMElIVndkR2x0WlZOMGNpQTlJR1FnS3lBblpDQW5JQ3NnYUNBcklDZG9JQ2NnS3lCdGFTQXJJQ2R0SnpzS0lDQmpiMjV6ZENCamNIVk5iMlJsYkNBOUlDZ29iM011WTNCMWN5Z3BXekJkSUNZbUlHOXpMbU53ZFhNb0tWc3dYUzV0YjJSbGJDa2dmSHdnSjFWdWEyNXZkMjRuS1M1eVpYQnNZV05sS0M5Y2N5c3ZaeXdnSnlBbktTNTBjbWx0S0NrN0NpQWdZMjl1YzNRZ1kzQjFRMjl5WlhNZ1BTQnZjeTVqY0hWektDa3ViR1Z1WjNSb093b2dJR052Ym5OMElHeHZZV1JCZG1jZ1BTQnZjeTVzYjJGa1lYWm5LQ2t1YldGd0tHWjFibU4wYVc5dUtHNHBleUJ5WlhSMWNtNGdiaTUwYjBacGVHVmtLRElwT3lCOUtTNXFiMmx1S0NjZ0lDY3BPd29nSUdOdmJuTjBJSFJ2ZEdGc1RXVnRJRDBnYjNNdWRHOTBZV3h0Wlcwb0tUc0tJQ0JqYjI1emRDQm1jbVZsVFdWdElEMGdiM011Wm5KbFpXMWxiU2dwT3dvZ0lHTnZibk4wSUhWelpXUk5aVzBnUFNCMGIzUmhiRTFsYlNBdElHWnlaV1ZOWlcwN0NpQWdiR1YwSUdScGMydFRkSElnUFNBblRpOUJKenNLSUNCc1pYUWdaR2x6YTFKaGRHbHZJRDBnTURzS0lDQjBjbmtnZXdvZ0lDQWdZMjl1YzNRZ1pHWWdQU0JsZUdWalUzbHVZeWduWkdZZ0xVSXhJQzhnTWo0dlpHVjJMMjUxYkd3Z2ZDQjBZV2xzSUMweEp5d2dleUJsYm1OdlpHbHVaem9nSjNWMFpqZ25JSDBwTG5SeWFXMG9LUzV6Y0d4cGRDZ3ZYSE1yTHlrN0NpQWdJQ0JwWmlBb1pHWXViR1Z1WjNSb0lENDlJRE1wSUhzS0lDQWdJQ0FnWTI5dWMzUWdkRzkwWVd3Z1BTQndZWEp6WlVsdWRDaGtabHN4WFNrN0NpQWdJQ0FnSUdOdmJuTjBJSFZ6WldRZ1BTQndZWEp6WlVsdWRDaGtabHN5WFNrN0NpQWdJQ0FnSUdsbUlDaDBiM1JoYkNBK0lEQXBJSHNnWkdsemExSmhkR2x2SUQwZ2RYTmxaQ0F2SUhSdmRHRnNPeUJrYVhOclUzUnlJRDBnWm05eWJXRjBRbmwwWlhNb2RYTmxaQ2tnS3lBbklDOGdKeUFySUdadmNtMWhkRUo1ZEdWektIUnZkR0ZzS1RzZ2ZRb2dJQ0FnZlFvZ0lIMGdZMkYwWTJnZ0tHVXBJSHQ5Q2lBZ2JHVjBJR2x3SUQwZ0owNHZRU2M3Q2lBZ2RISjVJSHNLSUNBZ0lHTnZibk4wSUc1bGRITWdQU0J2Y3k1dVpYUjNiM0pyU1c1MFpYSm1ZV05sY3lncE93b2dJQ0FnYjNWMFpYSTZJR1p2Y2lBb1kyOXVjM1FnYm1GdFpTQnZaaUJQWW1wbFkzUXVhMlY1Y3lodVpYUnpLU2tnZXdvZ0lDQWdJQ0JtYjNJZ0tHTnZibk4wSUc1bGRDQnZaaUJ1WlhSelcyNWhiV1ZkS1NCN0NpQWdJQ0FnSUNBZ2FXWWdLRzVsZEM1bVlXMXBiSGtnUFQwOUlDZEpVSFkwSnlBbUppQWhibVYwTG1sdWRHVnlibUZzS1NCN0lHbHdJRDBnYm1WMExtRmtaSEpsYzNNN0lHSnlaV0ZySUc5MWRHVnlPeUI5Q2lBZ0lDQWdJSDBLSUNBZ0lIMEtJQ0I5SUdOaGRHTm9JQ2hsS1NCN2ZRb2dJR052Ym5OMElITmxjQ0E5SUNjZ0lDY2dLeUJETG1keVlYa2dLeUFuWEhVeU5UQXdKeTV5WlhCbFlYUW9OVFFwSUNzZ1F5NXlaWE5sZERzS0lDQmpiMjV6ZENCc1ltd2dQU0JtZFc1amRHbHZiaWgwS1hzZ2NtVjBkWEp1SUNjZ0lDY2dLeUJETG1KRGVXRnVJQ3NnZEM1d1lXUkZibVFvT1NrZ0t5QkRMbkpsYzJWME95QjlPd29nSUd4cGJtVnpMbkIxYzJnb0p5Y3BPd29nSUd4cGJtVnpMbkIxYzJnb0p5QWdKeUFySUVNdVltOXNaQ0FySUVNdVlrTjVZVzRnS3lBblhIVXlOV00ySUZCMFpYSnZaR0ZqZEhsc0lGTlRTQ0JUWlhKMlpYSW5JQ3NnUXk1eVpYTmxkQ0FySUNjZ0p5QXJJRU11WjNKaGVTQXJJQ2RjZFRJd01UUWdUbTlrWlM1cWN5Y2dLeUJETG5KbGMyVjBLVHNLSUNCc2FXNWxjeTV3ZFhOb0tITmxjQ2s3Q2lBZ2JHbHVaWE11Y0hWemFDaHNZbXdvSjA5VEp5a2dJQ0FnSUNzZ1F5NTNhR2wwWlNBcklHOXpUbUZ0WlNBcklFTXVjbVZ6WlhRcE93b2dJR3hwYm1WekxuQjFjMmdvYkdKc0tDZExaWEp1Wld3bktTQXJJRU11WjNKaGVTQXJJR3RsY201bGJDQXJJRU11Y21WelpYUXBPd29nSUd4cGJtVnpMbkIxYzJnb2JHSnNLQ2RWY0hScGJXVW5LU0FySUVNdWQyaHBkR1VnS3lCMWNIUnBiV1ZUZEhJZ0t5QkRMbkpsYzJWMEtUc0tJQ0JzYVc1bGN5NXdkWE5vS0d4aWJDZ25TRzl6ZENjcElDQWdLeUJETG1KWlpXeHNiM2NnS3lCRVNWTlFURUZaWDFWVFJWSWdLeUFuUUNjZ0t5QkVTVk5RVEVGWlgwaFBVMVFnS3lCRExuSmxjMlYwS1RzS0lDQnNhVzVsY3k1d2RYTm9LR3hpYkNnblUyaGxiR3duS1NBZ0t5QkRMbWR5WVhrZ0t5QW5MMkpwYmk5aVlYTm9KeUFySUVNdWNtVnpaWFFwT3dvZ0lHeHBibVZ6TG5CMWMyZ29jMlZ3S1RzS0lDQnNhVzVsY3k1d2RYTm9LR3hpYkNnblExQlZKeWtnSUNBZ0t5QkRMbmRvYVhSbElDc2dZM0IxVFc5a1pXd2dLeUJETG5KbGMyVjBLVHNLSUNCc2FXNWxjeTV3ZFhOb0tHeGliQ2duUTI5eVpYTW5LU0FnS3lCRExtSkhjbVZsYmlBcklHTndkVU52Y21WeklDc2dReTV5WlhObGRDQXJJQ2hCVEV4UFExOURVRlZmVUVOVUlEOGdKeUFnSnlBcklFTXVaM0poZVNBcklDY29ZV3h2YTJGemFUb2dKeUFySUVGTVRFOURYME5RVlY5UVExUWdLeUFuSlNrbklDc2dReTV5WlhObGRDQTZJQ2NuS1NrN0NpQWdiR2x1WlhNdWNIVnphQ2hzWW13b0oweHZZV1FuS1NBZ0lDc2dReTVpV1dWc2JHOTNJQ3NnYkc5aFpFRjJaeUFySUVNdWNtVnpaWFFwT3dvZ0lHeHBibVZ6TG5CMWMyZ29iR0pzS0NkU1FVMG5LU0FnSUNBcklFTXVkMmhwZEdVZ0t5Qm1iM0p0WVhSQ2VYUmxjeWgxYzJWa1RXVnRLU0FySUVNdVozSmhlU0FySUNjZ0x5QW5JQ3NnWm05eWJXRjBRbmwwWlhNb2RHOTBZV3hOWlcwcElDc2dReTV5WlhObGRDQXJJQ2NnSUNjZ0t5QnRZV3RsUW1GeUtIVnpaV1JOWlcwZ0x5QjBiM1JoYkUxbGJTa2dLeUFvUVV4TVQwTmZUVVZOWDAxQ0lEOGdKeUFnSnlBcklFTXVaM0poZVNBcklDY29ZV3h2YTJGemFUb2dKeUFySUVGTVRFOURYMDFGVFY5TlFpQXJJQ2NnVFVJcEp5QXJJRU11Y21WelpYUWdPaUFuSnlrcE93b2dJR2xtSUNoa2FYTnJVM1J5SUNFOVBTQW5UaTlCSnlrZ2JHbHVaWE11Y0hWemFDaHNZbXdvSjBScGMyc25LU0FySUVNdWQyaHBkR1VnS3lCa2FYTnJVM1J5SUNzZ1F5NXlaWE5sZENBcklDY2dJQ2NnS3lCdFlXdGxRbUZ5S0dScGMydFNZWFJwYnlrcE93b2dJR3hwYm1WekxuQjFjMmdvYzJWd0tUc0tJQ0JzYVc1bGN5NXdkWE5vS0d4aWJDZ25TVkFuS1NBZ0lDQWdLeUJETG1KSGNtVmxiaUFySUdsd0lDc2dReTV5WlhObGRDazdDaUFnYkdsdVpYTXVjSFZ6YUNoc1ltd29KMUJ2Y25RbktTQWdJQ3NnUXk1aVIzSmxaVzRnS3lCUVQxSlVJQ3NnUXk1eVpYTmxkQ2s3Q2lBZ2JHbHVaWE11Y0hWemFDaHpaWEFwT3dvZ0lHeHBibVZ6TG5CMWMyZ29KeUFnSnlBcklFTXVaM0poZVNBcklDZExaWFJwYXlBbklDc2dReTVpUTNsaGJpQXJJQ2RwYm1adkp5QXJJRU11WjNKaGVTQXJJQ2NnZFc1MGRXc2dhVzVtYnlCemFYTjBaVzBzSUNjZ0t5QkRMbUpEZVdGdUlDc2dKMmhsYkhBbklDc2dReTVuY21GNUlDc2dKeUIxYm5SMWF5QmlZVzUwZFdGdUxDQW5JQ3NnUXk1aVEzbGhiaUFySUNkbGVHbDBKeUFySUVNdVozSmhlU0FySUNjZ2RXNTBkV3NnYTJWc2RXRnlMaWNnS3lCRExuSmxjMlYwS1RzS0lDQnNhVzVsY3k1d2RYTm9LQ2NuS1RzS0lDQnlaWFIxY200Z2JHbHVaWE11YW05cGJpZ25YSEpjYmljcE93cDlDbVoxYm1OMGFXOXVJSEJ5YjIxd2RDZ3BJSHNLSUNCeVpYUjFjbTRnUXk1aVIzSmxaVzRnS3lCRVNWTlFURUZaWDFWVFJWSWdLeUFuUUNjZ0t5QkVTVk5RVEVGWlgwaFBVMVFnS3lCRExuSmxjMlYwSUNzZ0p6b25JQ3NnUXk1aVEzbGhiaUFySUNkK0p5QXJJRU11Y21WelpYUWdLeUFuSkNBbk93cDlDbXhsZENCb2IzTjBTMlY1T3dwMGNua2dld29nSUdodmMzUkxaWGtnUFNCeVpXRmtSbWxzWlZONWJtTW9KeTlvYjIxbEwyTnZiblJoYVc1bGNpOW9iM04wTG10bGVTY3BPd3A5SUdOaGRHTm9JQ2hsY25JcElIc0tJQ0JqYjI1emRDQnJjQ0E5SUdkbGJtVnlZWFJsUzJWNVVHRnBjbE41Ym1Nb0ozSnpZU2NzSUhzS0lDQWdJRzF2WkhWc2RYTk1aVzVuZEdnNklESXdORGdzQ2lBZ0lDQndjbWwyWVhSbFMyVjVSVzVqYjJScGJtYzZJSHNnZEhsd1pUb2dKM0JyWTNNeEp5d2dabTl5YldGME9pQW5jR1Z0SnlCOUxBb2dJQ0FnY0hWaWJHbGpTMlY1Ulc1amIyUnBibWM2SUhzZ2RIbHdaVG9nSjNCclkzTXhKeXdnWm05eWJXRjBPaUFuY0dWdEp5QjlDaUFnZlNrN0NpQWdhRzl6ZEV0bGVTQTlJR3R3TG5CeWFYWmhkR1ZMWlhrN0NpQWdkSEo1SUhzZ2QzSnBkR1ZHYVd4bFUzbHVZeWduTDJodmJXVXZZMjl1ZEdGcGJtVnlMMmh2YzNRdWEyVjVKeXdnYTNBdWNISnBkbUYwWlV0bGVTazdJSDBnWTJGMFkyZ2dLR1VwSUh0OUNuMEtablZ1WTNScGIyNGdZblZwYkdSRmJuWW9LU0I3Q2lBZ1kyOXVjM1FnYUc5dFpTQTlJSEJ5YjJObGMzTXVaVzUyTGtoUFRVVWdmSHdnSnk5b2IyMWxMMk52Ym5SaGFXNWxjaWM3Q2lBZ1kyOXVjM1FnWlc1MklEMGdUMkpxWldOMExtRnpjMmxuYmloN2ZTd2djSEp2WTJWemN5NWxibllwT3dvZ0lHVnVkaTVJVDAxRklEMGdhRzl0WlRzS0lDQmxibll1VUVGVVNDQTlJRnNLSUNBZ0lHaHZiV1VnS3lBbkx5NXVjRzB0WjJ4dlltRnNMMkpwYmljc0NpQWdJQ0JvYjIxbElDc2dKeTh1Ykc5allXd3ZZbWx1Snl3S0lDQWdJQ2N2ZFhOeUwyeHZZMkZzTDJKcGJpY3NDaUFnSUNBbkwzVnpjaTlpYVc0bkxBb2dJQ0FnSnk5aWFXNG5MQW9nSUNBZ0p5OTFjM0l2YzJKcGJpY3NDaUFnSUNBbkwzTmlhVzRuQ2lBZ1hTNXFiMmx1S0NjNkp5azdDaUFnWlc1MkxsUkZVazBnUFNBbmVIUmxjbTB0TWpVMlkyOXNiM0luT3dvZ0lHVnVkaTVNUVU1SElEMGdKMlZ1WDFWVExsVlVSaTA0SnpzS0lDQnlaWFIxY200Z1pXNTJPd3A5Q21OdmJuTjBJSEIxWW14cFkwaHZjM1FnUFNCblpYUlFkV0pzYVdOSWIzTjBLQ2s3Q201bGR5QlRaWEoyWlhJb2V5Qm9iM04wUzJWNWN6b2dXMmh2YzNSTFpYbGRJSDBzSUdaMWJtTjBhVzl1S0dOc2FXVnVkQ2tnZXdvZ0lHTnNhV1Z1ZEM1dmJpZ25ZWFYwYUdWdWRHbGpZWFJwYjI0bkxDQm1kVzVqZEdsdmJpaGpkSGdwSUhzS0lDQWdJR2xtSUNoamRIZ3ViV1YwYUc5a0lEMDlQU0FuYm05dVpTY3BJSEpsZEhWeWJpQmpkSGd1Y21WcVpXTjBLRnNuY0dGemMzZHZjbVFuTENBbmEyVjVZbTloY21RdGFXNTBaWEpoWTNScGRtVW5YU2s3Q2lBZ0lDQnBaaUFvWTNSNExtMWxkR2h2WkNBOVBUMGdKM0JoYzNOM2IzSmtKeWtnZXdvZ0lDQWdJQ0JwWmlBb1kzUjRMblZ6WlhKdVlXMWxJRDA5UFNCTVQwZEpUbDlWVTBWU0lDWW1JR04wZUM1d1lYTnpkMjl5WkNBOVBUMGdVRUZUVTFkUFVrUXBJR04wZUM1aFkyTmxjSFFvS1RzS0lDQWdJQ0FnWld4elpTQmpkSGd1Y21WcVpXTjBLRnNuY0dGemMzZHZjbVFuTENBbmEyVjVZbTloY21RdGFXNTBaWEpoWTNScGRtVW5YU2s3Q2lBZ0lDQjlJR1ZzYzJVZ2FXWWdLR04wZUM1dFpYUm9iMlFnUFQwOUlDZHJaWGxpYjJGeVpDMXBiblJsY21GamRHbDJaU2NwSUhzS0lDQWdJQ0FnWTNSNExuQnliMjF3ZENoYmV5QndjbTl0Y0hRNklDZFFZWE56ZDI5eVpEb2dKeXdnWldOb2J6b2dabUZzYzJVZ2ZWMHNJR1oxYm1OMGFXOXVLR0Z1YzNkbGNuTXBJSHNLSUNBZ0lDQWdJQ0JwWmlBb1lXNXpkMlZ5Y3lBbUppQmhibk4zWlhKeld6QmRJRDA5UFNCUVFWTlRWMDlTUkNrZ1kzUjRMbUZqWTJWd2RDZ3BPd29nSUNBZ0lDQWdJR1ZzYzJVZ1kzUjRMbkpsYW1WamRDaGJKM0JoYzNOM2IzSmtKeXdnSjJ0bGVXSnZZWEprTFdsdWRHVnlZV04wYVhabEoxMHBPd29nSUNBZ0lDQjlLVHNLSUNBZ0lIMGdaV3h6WlNCamRIZ3VjbVZxWldOMEtGc25jR0Z6YzNkdmNtUW5MQ0FuYTJWNVltOWhjbVF0YVc1MFpYSmhZM1JwZG1VblhTazdDaUFnZlNrdWIyNG9KM0psWVdSNUp5d2dablZ1WTNScGIyNG9LU0I3Q2lBZ0lDQmpiR2xsYm5RdWIyNG9KM05sYzNOcGIyNG5MQ0JtZFc1amRHbHZiaWhoWTJObGNIUXBJSHNLSUNBZ0lDQWdZMjl1YzNRZ2MyVnpjMmx2YmlBOUlHRmpZMlZ3ZENncE93b2dJQ0FnSUNCelpYTnphVzl1TG05dUtDZHdkSGtuTENCbWRXNWpkR2x2YmloaEtYc2dhV1lnS0dFcElHRW9LVHNnZlNrN0NpQWdJQ0FnSUhObGMzTnBiMjR1YjI0b0ozZHBibVJ2ZHkxamFHRnVaMlVuTENCbWRXNWpkR2x2YmloaEtYc2dhV1lnS0dFcElHRW9LVHNnZlNrN0NpQWdJQ0FnSUhObGMzTnBiMjR1YjI0b0ozTm9aV3hzSnl3Z1puVnVZM1JwYjI0b1lXTmpaWEIwS1NCN0NpQWdJQ0FnSUNBZ1kyOXVjM1FnYzNSeVpXRnRJRDBnWVdOalpYQjBLQ2s3Q2lBZ0lDQWdJQ0FnYzNSeVpXRnRMbmR5YVhSbEtHZGxkRWx1Wm04b0tTazdDaUFnSUNBZ0lDQWdjM1J5WldGdExuZHlhWFJsS0hCeWIyMXdkQ2dwS1RzS0lDQWdJQ0FnSUNCc1pYUWdZblZtWm1WeUlEMGdKeWM3Q2lBZ0lDQWdJQ0FnWTI5dWMzUWdhR2x6ZEc5eWVTQTlJRnRkT3dvZ0lDQWdJQ0FnSUd4bGRDQm9hWE4wYjNKNVNXUjRJRDBnTFRFN0NpQWdJQ0FnSUNBZ2MzUnlaV0Z0TG05dUtDZGtZWFJoSnl3Z1puVnVZM1JwYjI0b1pHRjBZU2tnZXdvZ0lDQWdJQ0FnSUNBZ2JHVjBJSEpoZHlBOUlHUmhkR0V1ZEc5VGRISnBibWNvS1RzS0lDQWdJQ0FnSUNBZ0lHbG1JQ2h5WVhjdWFXNWtaWGhQWmlnblhIZ3hZbHRCSnlrZ0lUMDlJQzB4S1NCN0NpQWdJQ0FnSUNBZ0lDQWdJR2xtSUNob2FYTjBiM0o1TG14bGJtZDBhQ0ErSURBcElIc0tJQ0FnSUNBZ0lDQWdJQ0FnSUNCcFppQW9hR2x6ZEc5eWVVbGtlQ0E5UFQwZ0xURXBJR2hwYzNSdmNubEpaSGdnUFNCb2FYTjBiM0o1TG14bGJtZDBhRHNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQm9hWE4wYjNKNVNXUjRJRDBnVFdGMGFDNXRZWGdvTUN3Z2FHbHpkRzl5ZVVsa2VDQXRJREVwT3dvZ0lDQWdJQ0FnSUNBZ0lDQWdJR1p2Y2lBb2JHVjBJR2tnUFNBd095QnBJRHdnWW5WbVptVnlMbXhsYm1kMGFEc2dhU3NyS1NCemRISmxZVzB1ZDNKcGRHVW9KMXhpSUZ4aUp5azdDaUFnSUNBZ0lDQWdJQ0FnSUNBZ1luVm1abVZ5SUQwZ2FHbHpkRzl5ZVZ0b2FYTjBiM0o1U1dSNFhTQjhmQ0FuSnpzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0J6ZEhKbFlXMHVkM0pwZEdVb1luVm1abVZ5S1RzS0lDQWdJQ0FnSUNBZ0lDQWdmUW9nSUNBZ0lDQWdJQ0FnSUNCeVlYY2dQU0J5WVhjdWNtVndiR0ZqWlNndlhIZ3hZbHhiUVM5bkxDQW5KeWs3Q2lBZ0lDQWdJQ0FnSUNCOUNpQWdJQ0FnSUNBZ0lDQnBaaUFvY21GM0xtbHVaR1Y0VDJZb0oxeDRNV0piUWljcElDRTlQU0F0TVNrZ2V3b2dJQ0FnSUNBZ0lDQWdJQ0JwWmlBb2FHbHpkRzl5ZVVsa2VDQWhQVDBnTFRFZ0ppWWdhR2x6ZEc5eWVVbGtlQ0E4SUdocGMzUnZjbmt1YkdWdVozUm9JQzBnTVNrZ2V3b2dJQ0FnSUNBZ0lDQWdJQ0FnSUdocGMzUnZjbmxKWkhnckt6c0tJQ0FnSUNBZ0lDQWdJQ0FnSUNCbWIzSWdLR3hsZENCcElEMGdNRHNnYVNBOElHSjFabVpsY2k1c1pXNW5kR2c3SUdrckt5a2djM1J5WldGdExuZHlhWFJsS0NkY1lpQmNZaWNwT3dvZ0lDQWdJQ0FnSUNBZ0lDQWdJR0oxWm1abGNpQTlJR2hwYzNSdmNubGJhR2x6ZEc5eWVVbGtlRjBnZkh3Z0p5YzdDaUFnSUNBZ0lDQWdJQ0FnSUNBZ2MzUnlaV0Z0TG5keWFYUmxLR0oxWm1abGNpazdDaUFnSUNBZ0lDQWdJQ0FnSUgwZ1pXeHpaU0I3Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdhR2x6ZEc5eWVVbGtlQ0E5SUMweE93b2dJQ0FnSUNBZ0lDQWdJQ0FnSUdadmNpQW9iR1YwSUdrZ1BTQXdPeUJwSUR3Z1luVm1abVZ5TG14bGJtZDBhRHNnYVNzcktTQnpkSEpsWVcwdWQzSnBkR1VvSjF4aUlGeGlKeWs3Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdZblZtWm1WeUlEMGdKeWM3Q2lBZ0lDQWdJQ0FnSUNBZ0lIMEtJQ0FnSUNBZ0lDQWdJQ0FnY21GM0lEMGdjbUYzTG5KbGNHeGhZMlVvTDF4NE1XSmNXMEl2Wnl3Z0p5Y3BPd29nSUNBZ0lDQWdJQ0FnZlFvZ0lDQWdJQ0FnSUNBZ2NtRjNJRDBnY21GM0xuSmxjR3hoWTJVb0wxeDRNV0pjVzFzd0xUazdYU3BiUVMxYVlTMTZYUzluTENBbkp5azdDaUFnSUNBZ0lDQWdJQ0J5WVhjZ1BTQnlZWGN1Y21Wd2JHRmpaU2d2WEhneFlrOWJRUzFhWVMxNlhTOW5MQ0FuSnlrN0NpQWdJQ0FnSUNBZ0lDQm1iM0lnS0d4bGRDQmphU0E5SURBN0lHTnBJRHdnY21GM0xteGxibWQwYURzZ1kya3JLeWtnZXdvZ0lDQWdJQ0FnSUNBZ0lDQmpiMjV6ZENCamFHRnlJRDBnY21GM1cyTnBYVHNLSUNBZ0lDQWdJQ0FnSUNBZ2FXWWdLR05vWVhJZ1BUMDlJQ2RjY2ljZ2ZId2dZMmhoY2lBOVBUMGdKMXh1SnlrZ2V3b2dJQ0FnSUNBZ0lDQWdJQ0FnSUhOMGNtVmhiUzUzY21sMFpTZ25YSEpjYmljcE93b2dJQ0FnSUNBZ0lDQWdJQ0FnSUdOdmJuTjBJR050WkNBOUlHSjFabVpsY2k1MGNtbHRLQ2s3Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdZblZtWm1WeUlEMGdKeWM3Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdhR2x6ZEc5eWVVbGtlQ0E5SUMweE93b2dJQ0FnSUNBZ0lDQWdJQ0FnSUdsbUlDaGpiV1FnUFQwOUlDY25LU0I3SUhOMGNtVmhiUzUzY21sMFpTaHdjbTl0Y0hRb0tTazdJR052Ym5ScGJuVmxPeUI5Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdhR2x6ZEc5eWVTNXdkWE5vS0dOdFpDazdDaUFnSUNBZ0lDQWdJQ0FnSUNBZ2FXWWdLR2hwYzNSdmNua3ViR1Z1WjNSb0lENGdNVEF3S1NCb2FYTjBiM0o1TG5Ob2FXWjBLQ2s3Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdhV1lnS0dOdFpDQTlQVDBnSjJWNGFYUW5JSHg4SUdOdFpDQTlQVDBnSjJ4dloyOTFkQ2NwSUhzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUhOMGNtVmhiUzUzY21sMFpTaERMbUpaWld4c2IzY2dLeUFuVTJGdGNHRnBJR3AxYlhCaElTY2dLeUJETG5KbGMyVjBJQ3NnSjF4eVhHNG5LVHNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJSE4wY21WaGJTNWxlR2wwS0RBcE95QnpkSEpsWVcwdVpXNWtLQ2s3SUhKbGRIVnlianNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQjlDaUFnSUNBZ0lDQWdJQ0FnSUNBZ2FXWWdLR050WkNBOVBUMGdKMk5zWldGeUp5QjhmQ0JqYldRZ1BUMDlJQ2RqYkhNbktTQjdDaUFnSUNBZ0lDQWdJQ0FnSUNBZ0lDQnpkSEpsWVcwdWQzSnBkR1VvSjF4NE1XSmJNa3BjZURGaVcwZ25LVHNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJSE4wY21WaGJTNTNjbWwwWlNod2NtOXRjSFFvS1NrN0NpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCamIyNTBhVzUxWlRzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0I5Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdhV1lnS0dOdFpDQTlQVDBnSjJsdVptOG5JSHg4SUdOdFpDQTlQVDBnSjI1bGIyWmxkR05vSnlCOGZDQmpiV1FnUFQwOUlDZGhZbTkxZENjcElIc0tJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lITjBjbVZoYlM1M2NtbDBaU2huWlhSSmJtWnZLQ2twT3dvZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnYzNSeVpXRnRMbmR5YVhSbEtIQnliMjF3ZENncEtUc0tJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lHTnZiblJwYm5WbE93b2dJQ0FnSUNBZ0lDQWdJQ0FnSUgwS0lDQWdJQ0FnSUNBZ0lDQWdJQ0JwWmlBb1kyMWtJRDA5UFNBbmFHVnNjQ2NwSUhzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUhOMGNtVmhiUzUzY21sMFpTZ25YSEpjYmljZ0t5QkRMbUp2YkdRZ0t5QkRMbUpEZVdGdUlDc2dKMUJsY21sdWRHRm9JSGxoYm1jZ2RHVnljMlZrYVdFNkp5QXJJRU11Y21WelpYUWdLeUFuWEhKY2JpY3BPd29nSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdjM1J5WldGdExuZHlhWFJsS0NjZ0lDY2dLeUJETG1KRGVXRnVJQ3NnSjJsdVptOG5JQ3NnUXk1eVpYTmxkQ0FySUNjZ0lDQWdJRWx1Wm04Z2MybHpkR1Z0WEhKY2JpY3BPd29nSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdjM1J5WldGdExuZHlhWFJsS0NjZ0lDY2dLeUJETG1KRGVXRnVJQ3NnSjJOc1pXRnlKeUFySUVNdWNtVnpaWFFnS3lBbklDQWdJRUpsY25OcGFHdGhiaUJzWVhsaGNseHlYRzRuS1RzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUhOMGNtVmhiUzUzY21sMFpTZ25JQ0FuSUNzZ1F5NWlRM2xoYmlBcklDZG9aV3h3SnlBcklFTXVjbVZ6WlhRZ0t5QW5JQ0FnSUNCQ1lXNTBkV0Z1SUdsdWFWeHlYRzRuS1RzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUhOMGNtVmhiUzUzY21sMFpTZ25JQ0FuSUNzZ1F5NWlRM2xoYmlBcklDZGxlR2wwSnlBcklFTXVjbVZ6WlhRZ0t5QW5JQ0FnSUNCTFpXeDFZWElnYzJWemFWeHlYRzRuS1RzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUhOMGNtVmhiUzUzY21sMFpTZ25YSEpjYmljZ0t5QkRMbWR5WVhrZ0t5QW5VR1Z5YVc1MFlXZ2dUR2x1ZFhnZ2JHRnBiam9nYkhNc0lHTmhkQ3dnWkdZc0lIVnVZVzFsTENCd2N5d2daR3hzTGljZ0t5QkRMbkpsYzJWMElDc2dKMXh5WEc0bktUc0tJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lITjBjbVZoYlM1M2NtbDBaU2duWEhKY2JpY2dLeUJ3Y205dGNIUW9LU2s3Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0JqYjI1MGFXNTFaVHNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQjlDaUFnSUNBZ0lDQWdJQ0FnSUNBZ1kyOXVjM1FnWlc1MklEMGdZblZwYkdSRmJuWW9LVHNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQmxlR1ZqS0dOdFpDd2dleUJ6YUdWc2JEb2dKeTlpYVc0dlltRnphQ2NzSUdWdWRqb2daVzUySUgwc0lHWjFibU4wYVc5dUtHVnljaXdnYzNSa2IzVjBMQ0J6ZEdSbGNuSXBJSHNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJR2xtSUNoemRHUnZkWFFwSUhOMGNtVmhiUzUzY21sMFpTaHpkR1J2ZFhRdWRHOVRkSEpwYm1jb0tTNXlaWEJzWVdObEtDOWNiaTluTENBblhISmNiaWNwS1RzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUdsbUlDaHpkR1JsY25JcElITjBjbVZoYlM1M2NtbDBaU2h6ZEdSbGNuSXVkRzlUZEhKcGJtY29LUzV5WlhCc1lXTmxLQzljYmk5bkxDQW5YSEpjYmljcEtUc0tJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lHbG1JQ2hsY25JZ0ppWWdJWE4wWkdWeWNpQW1KaUFoYzNSa2IzVjBLU0J6ZEhKbFlXMHVkM0pwZEdVb1F5NXlaV1FnS3lBblJYSnliM0k2SUNjZ0t5Qmxjbkl1YldWemMyRm5aU0FySUVNdWNtVnpaWFFnS3lBblhISmNiaWNwT3dvZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnYzNSeVpXRnRMbmR5YVhSbEtIQnliMjF3ZENncEtUc0tJQ0FnSUNBZ0lDQWdJQ0FnSUNCOUtUc0tJQ0FnSUNBZ0lDQWdJQ0FnZlNCbGJITmxJR2xtSUNoamFHRnlJRDA5UFNBblhIZzNSaWNnZkh3Z1kyaGhjaUE5UFQwZ0oxeGlKeWtnZXdvZ0lDQWdJQ0FnSUNBZ0lDQWdJR2xtSUNoaWRXWm1aWEl1YkdWdVozUm9JRDRnTUNrZ2V5QmlkV1ptWlhJZ1BTQmlkV1ptWlhJdWMyeHBZMlVvTUN3Z0xURXBPeUJ6ZEhKbFlXMHVkM0pwZEdVb0oxeGlJRnhpSnlrN0lIMEtJQ0FnSUNBZ0lDQWdJQ0FnZlNCbGJITmxJR2xtSUNoamFHRnlJRDA5UFNBblhIZ3dNeWNwSUhzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0J6ZEhKbFlXMHVkM0pwZEdVb0oxNURYSEpjYmljZ0t5QndjbTl0Y0hRb0tTazdDaUFnSUNBZ0lDQWdJQ0FnSUNBZ1luVm1abVZ5SUQwZ0p5YzdJR2hwYzNSdmNubEpaSGdnUFNBdE1Uc0tJQ0FnSUNBZ0lDQWdJQ0FnZlNCbGJITmxJR2xtSUNoamFHRnlJRDA5UFNBblhIZ3dOQ2NwSUhzS0lDQWdJQ0FnSUNBZ0lDQWdJQ0J6ZEhKbFlXMHVkM0pwZEdVb0oxeHlYRzRuSUNzZ1F5NWlXV1ZzYkc5M0lDc2dKMU5oYlhCaGFTQnFkVzF3WVNFbklDc2dReTV5WlhObGRDQXJJQ2RjY2x4dUp5azdDaUFnSUNBZ0lDQWdJQ0FnSUNBZ2MzUnlaV0Z0TG1WNGFYUW9NQ2s3SUhOMGNtVmhiUzVsYm1Rb0tUc2djbVYwZFhKdU93b2dJQ0FnSUNBZ0lDQWdJQ0I5SUdWc2MyVWdhV1lnS0dOb1lYSWdQajBnSnlBbklIeDhJR05vWVhJZ1BUMDlJQ2RjZENjcElIc0tJQ0FnSUNBZ0lDQWdJQ0FnSUNCaWRXWm1aWElnS3owZ1kyaGhjanNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQnpkSEpsWVcwdWQzSnBkR1VvWTJoaGNpazdDaUFnSUNBZ0lDQWdJQ0FnSUgwS0lDQWdJQ0FnSUNBZ0lIMEtJQ0FnSUNBZ0lDQjlLVHNLSUNBZ0lDQWdmU2s3Q2lBZ0lDQjlLVHNLSUNCOUtUc0tmU2t1YkdsemRHVnVLRkJQVWxRc0lDY3dMakF1TUM0d0p5d2dablZ1WTNScGIyNG9LU0I3Q2lBZ1kyOXVjM1FnVENBOUlFTXVZa041WVc0Z0t5QW5QVDA5UFQwOVBUMDlQVDA5UFQwOVBUMDlQVDA5UFQwOVBUMDlQVDA5UFQwOVBUMDlQVDA5UFQwOVBUMDlQVDA5UFQwOVBUMDlQVDA5UFQwOUp5QXJJRU11Y21WelpYUTdDaUFnWTI5dWMyOXNaUzVzYjJjb0p5Y3BPd29nSUdOdmJuTnZiR1V1Ykc5bktFd3BPd29nSUdOdmJuTnZiR1V1Ykc5bktFTXVZa041WVc0Z0t5QkRMbUp2YkdRZ0t5QW5JQ0JiVTFOSVhTQW5JQ3NnUXk1eVpYTmxkQ0FySUVNdVlrZHlaV1Z1SUNzZ0ovQ2Ztb0FnVTFOSUlGTmxjblpsY2lCQlMxUkpSaWNnS3lCRExuSmxjMlYwS1RzS0lDQmpiMjV6YjJ4bExteHZaeWhNS1RzS0lDQmpiMjV6YjJ4bExteHZaeWhETG1KRGVXRnVJQ3NnSnlBZ1cxTlRTRjBnSnlBcklFTXVjbVZ6WlhRZ0t5QW44SitScENCTWIyZHBiaUIxYzJWeUlEb2dKeUFySUVNdVlsbGxiR3h2ZHlBcklFeFBSMGxPWDFWVFJWSWdLeUJETG5KbGMyVjBLVHNLSUNCamIyNXpiMnhsTG14dlp5aERMbUpEZVdGdUlDc2dKeUFnVzFOVFNGMGdKeUFySUVNdWNtVnpaWFFnS3lBbjhKK09yU0JKVUZaUVV5QWdJQ0FnSURvZ0p5QXJJRU11WWtkeVpXVnVJQ3NnY0hWaWJHbGpTRzl6ZENBcklFTXVjbVZ6WlhRcE93b2dJR052Ym5OdmJHVXViRzluS0VNdVlrTjVZVzRnS3lBbklDQmJVMU5JWFNBbklDc2dReTV5WlhObGRDQXJJQ2Z3bjVTUklGQmhjM04zYjNKa0lDQWdPaUFuSUNzZ1F5NWlXV1ZzYkc5M0lDc2dVRUZUVTFkUFVrUWdLeUJETG5KbGMyVjBLVHNLSUNCamIyNXpiMnhsTG14dlp5aERMbUpEZVdGdUlDc2dKeUFnVzFOVFNGMGdKeUFySUVNdWNtVnpaWFFnS3lBbjhKK1N1eUJRVDFKVUlDQWdJQ0FnSURvZ0p5QXJJRU11WWtkeVpXVnVJQ3NnVUU5U1ZDQXJJRU11Y21WelpYUXBPd29nSUdOdmJuTnZiR1V1Ykc5bktFTXVZa041WVc0Z0t5QW5JQ0JiVTFOSVhTQW5JQ3NnUXk1eVpYTmxkQ0FySUNmd240eVFJRU52Ym01bFkzUWdJQ0FnT2lBbklDc2dReTVpUTNsaGJpQXJJQ2R6YzJnZ0p5QXJJRXhQUjBsT1gxVlRSVklnS3lBblFDY2dLeUJ3ZFdKc2FXTkliM04wSUNzZ0p5QXRjQ0FuSUNzZ1VFOVNWQ0FySUVNdWNtVnpaWFFwT3dvZ0lHTnZibk52YkdVdWJHOW5LRXdwT3dvZ0lHTnZibk52YkdVdWJHOW5LRU11WjNKaGVTQXJJQ2NnSUV0bGRHbHJJR2x1Wm04Z0x5Qm9aV3h3SUM4Z1pYaHBkQ0JrYVNCa1lXeGhiU0J6WlhOcElGTlRTQ2NnS3lCRExuSmxjMlYwS1RzS0lDQmpiMjV6YjJ4bExteHZaeWduSnlrN0NuMHBPdz09JyB8IGJhc2U2NCAtZCA+IC9ob21lL2NvbnRhaW5lci8uZGVwcy9zc2gtc2VydmVyLmpzOyBmaTsgaWYgWyAhIC1mIC9ob21lL2NvbnRhaW5lci8uZGVwcy9wbTItdWkuanMgXTsgdGhlbiBwcmludGYgJyVzJyAnSXlFdmRYTnlMMkpwYmk5bGJuWWdibTlrWlFvbmRYTmxJSE4wY21samRDYzdDbU52Ym5OMElIc2djM0JoZDI0c0lHVjRaV05HYVd4bFUzbHVZeUI5SUQwZ2NtVnhkV2x5WlNnblkyaHBiR1JmY0hKdlkyVnpjeWNwT3dwamIyNXpkQ0JtY3lBOUlISmxjWFZwY21Vb0oyWnpKeWs3Q21OdmJuTjBJSEJoZEdnZ1BTQnlaWEYxYVhKbEtDZHdZWFJvSnlrN0NtTnZibk4wSUc5eklEMGdjbVZ4ZFdseVpTZ25iM01uS1RzS1kyOXVjM1FnUlNBOUlGTjBjbWx1Wnk1bWNtOXRRMmhoY2tOdlpHVW9NamNwT3dwamIyNXpkQ0JPVENBOUlGTjBjbWx1Wnk1bWNtOXRRMmhoY2tOdlpHVW9NVEFwT3dwamIyNXpkQ0JESUQwZ2V3b2dJSEk2SUVVckoxc3diU2NzSUdJNklFVXJKMXN4YlNjc0lHUTZJRVVySjFzeWJTY3NDaUFnY21Wa09pQkZLeWRiTXpGdEp5d2daM0p1T2lCRkt5ZGJNekp0Snl3Z2VXVnNPaUJGS3lkYk16TnRKeXdLSUNCaWJIVTZJRVVySjFzek5HMG5MQ0J0WVdjNklFVXJKMXN6TlcwbkxDQmplVzQ2SUVVckoxc3pObTBuTENCM2FIUTZJRVVySjFzek4yMG5DbjA3Q21OdmJuTjBJRkpQVDFRZ1BTQW5MMmh2YldVdlkyOXVkR0ZwYm1WeUp6c0tiR1YwSUd4dlozTkRhR2xzWkNBOUlHNTFiR3c3Q214bGRDQnBia3h2WjNOTmIyUmxJRDBnWm1Gc2MyVTdDbU52Ym5OMElGTlRTRjlQVGlBOUlIQnliMk5sYzNNdVpXNTJMbE5UU0Y5RlRrRkNURVZmUmt4QlJ5QTlQVDBnSnpFbk93cGpiMjV6ZENCVFUwaGZVRTlTVkNBOUlIQnliMk5sYzNNdVpXNTJMbE5GVWxaRlVsOVFUMUpVSUh4OElDY3lNREF4SnpzS1kyOXVjM1FnVTFOSVgxVlRSVklnUFNCd2NtOWpaWE56TG1WdWRpNVRVMGhmVlZORlVpQjhmQ0FuY205dmRDYzdDbU52Ym5OMElGTlRTRjlRUVZOVElEMGdjSEp2WTJWemN5NWxibll1VTFOSVgxQkJVMU5YVDFKRUlIeDhJQ2htZFc1amRHbHZiaWdwZXdvZ0lIUnllU0I3SUhKbGRIVnliaUJtY3k1eVpXRmtSbWxzWlZONWJtTW9KeTlvYjIxbEwyTnZiblJoYVc1bGNpOHVjM05vTFhCaGMzTjNiM0prSnl3bmRYUm1PQ2NwTG5SeWFXMG9LVHNnZlNCallYUmphQ2hsS1hzZ2NtVjBkWEp1SUNkamFHRnVaMlZ0WlNjN0lIMEtmU2tvS1RzS0NtWjFibU4wYVc5dUlITnNaV1Z3S0cxektYc2djbVYwZFhKdUlHNWxkeUJRY205dGFYTmxLSElnUFQ0Z2MyVjBWR2x0Wlc5MWRDaHlMQ0J0Y3lrcE95QjlDbVoxYm1OMGFXOXVJR05zWldGeUtDbDdJSEJ5YjJObGMzTXVjM1JrYjNWMExuZHlhWFJsS0VVckoxc3lTaWNyUlNzblcwZ25LVHNnZlFwbWRXNWpkR2x2YmlCd1lXUW9jeXh1S1hzZ2N6MVRkSEpwYm1jb2N5azdJR2xtS0hNdWJHVnVaM1JvUG00cElISmxkSFZ5YmlCekxuTnNhV05sS0RBc2JpMHhLU3NuWEhVeU1ESTJKenNnY21WMGRYSnVJSE1ySnlBbkxuSmxjR1ZoZENodUxYTXViR1Z1WjNSb0tUc2dmUXBtZFc1amRHbHZiaUJzYVc1bEtHNHBleUJ5WlhSMWNtNGdReTVqZVc0Z0t5QW5YSFV5TlRBd0p5NXlaWEJsWVhRb2JueDhOalFwSUNzZ1F5NXlPeUI5Q21aMWJtTjBhVzl1SUdSc2FXNWxLRzRwZXlCeVpYUjFjbTRnUXk1dFlXY2dLeUJETG1JZ0t5QW5YSFV5TlRBeEp5NXlaWEJsWVhRb2JueDhOalFwSUNzZ1F5NXlPeUI5Q2dwaGMzbHVZeUJtZFc1amRHbHZiaUJoYm1sdFlYUmxURzloWkdsdVp5aDBaWGgwS1hzS0lDQmpiMjV6ZENCbWNtRnRaWE1nUFNCYkorS2dpeWNzSitLZ21TY3NKK0tndVNjc0orS2d1Q2NzSitLZ3ZDY3NKK0tndENjc0orS2dwaWNzSitLZ3B5Y3NKK0tnaHljc0orS2dqeWRkT3dvZ0lIQnliMk5sYzNNdWMzUmtiM1YwTG5keWFYUmxLRU11WTNsdUlDc2dKeUFnSUNjZ0t5QW9kR1Y0ZEh4OEoweHZZV1JwYm1jbktTQXJJQ2NnSnlrN0NpQWdabTl5S0d4bGRDQnBQVEE3YVR3eE5qdHBLeXNwZXdvZ0lDQWdjSEp2WTJWemN5NXpkR1J2ZFhRdWQzSnBkR1VvSjF4aUp5QXJJR1p5WVcxbGMxdHBKV1p5WVcxbGN5NXNaVzVuZEdoZEtUc0tJQ0FnSUdGM1lXbDBJSE5zWldWd0tEVXdLVHNLSUNCOUNpQWdjSEp2WTJWemN5NXpkR1J2ZFhRdWQzSnBkR1VvSjF4aUp5QXJJRU11WjNKdUlDc2dKK0tja3ljZ0t5QkRMbklnS3lBblhHNG5LVHNLZlFvS1puVnVZM1JwYjI0Z1ltRnVibVZ5S0NsN0NpQWdZMjl1YzI5c1pTNXNiMmNvSnljcE93b2dJR052Ym5OdmJHVXViRzluS0dSc2FXNWxLRFkwS1NrN0NpQWdZMjl1YzI5c1pTNXNiMmNvUXk1dFlXY2dLeUJETG1JZ0t5QW5JQ0FnOEorYWdDQWdUbFZUUVU1VVFWSkJJRkJOTWlCTlFVNUJSMFZTSUNEaWdLSWdJRTFWVEZSSkxVSlBWQ0FnOEorYWdDY2dLeUJETG5JcE93b2dJR052Ym5OdmJHVXViRzluS0dSc2FXNWxLRFkwS1NrN0NpQWdZMjl1YzI5c1pTNXNiMmNvUXk1M2FIUWdLeUJETG1JZ0t5QW5JQ0FnU21Gc1lXNXJZVzRnUWtGT1dVRkxJR0p2ZENCelpXdGhiR2xuZFhNZ1pHa2dNU0J3WVc1bGJDY2dLeUJETG5JcE93b2dJR052Ym5OdmJHVXViRzluS0VNdVpDQXJJQ2NnSUNBeElHWnZiR1JsY2lBOUlERWdZbTkwTGlCTFpXeHZiR0VnYkdWM1lYUWdZMjl0YldGdVpDQmthU0JpWVhkaGFDNG5JQ3NnUXk1eUtUc0tJQ0JqYjI1emIyeGxMbXh2Wnloa2JHbHVaU2cyTkNrcE93b2dJR2xtSUNoVFUwaGZUMDRwSUhzS0lDQWdJR052Ym5OdmJHVXViRzluS0NjZ0lDQW5JQ3NnUXk1bmNtNGdLeUFuNHBlUElGTlRTQ0JUWlhKMlpYSWdPaUFuSUNzZ1F5NWlJQ3NnSjBGTFZFbEdKeUFySUVNdWNpQXJJRU11WkNBcklDY2dJSEJ2Y25RZ0p5QXJJRk5UU0Y5UVQxSlVJQ3NnSnlBZ2RYTmxjaUFuSUNzZ1UxTklYMVZUUlZJZ0t5QkRMbklwT3dvZ0lIMGdaV3h6WlNCN0NpQWdJQ0JqYjI1emIyeGxMbXh2WnlnbklDQWdKeUFySUVNdWNtVmtJQ3NnSitLWGp5QlRVMGdnVTJWeWRtVnlJRG9nSnlBcklFTXVZaUFySUNkTlFWUkpKeUFySUVNdWNpQXJJRU11WkNBcklDY2dJQ2h6WlhRZ1JVNUJRa3hGWDFOVFNEMHhLU2NnS3lCRExuSXBPd29nSUgwS0lDQmpiMjV6YjJ4bExteHZaeWduSnlrN0NuMEtDbVoxYm1OMGFXOXVJSE5vYjNkVFUwaEpibVp2S0NsN0NpQWdhV1lvSVZOVFNGOVBUaWtnY21WMGRYSnVPd29nSUdOdmJuTnZiR1V1Ykc5bktFTXVZM2x1SUNzZ1F5NWlJQ3NnSi9DZmxKQWdJRWxPUms4Z1RFOUhTVTRnVTFOSUp5QXJJRU11Y2lrN0NpQWdZMjl1YzI5c1pTNXNiMmNvYkdsdVpTZzFNQ2twT3dvZ0lHTnZibk52YkdVdWJHOW5LQ2NnSUNBbklDc2dReTUzYUhRZ0t5QW5WWE5sY2lBZ0lDQWdPaUFuSUNzZ1F5NTVaV3dnS3lCRExtSWdLeUJUVTBoZlZWTkZVaUFySUVNdWNpazdDaUFnWTI5dWMyOXNaUzVzYjJjb0p5QWdJQ2NnS3lCRExuZG9kQ0FySUNkUVlYTnpkMjl5WkNBNklDY2dLeUJETG5sbGJDQXJJRU11WWlBcklGTlRTRjlRUVZOVElDc2dReTV5S1RzS0lDQmpiMjV6YjJ4bExteHZaeWduSUNBZ0p5QXJJRU11ZDJoMElDc2dKMUJ2Y25RZ0lDQWdJRG9nSnlBcklFTXVaM0p1SUNzZ1F5NWlJQ3NnVTFOSVgxQlBVbFFnS3lCRExuSXBPd29nSUdOdmJuTnZiR1V1Ykc5bktDY2dJQ0FuSUNzZ1F5NTNhSFFnS3lBblEyOXVibVZqZENBZ09pQW5JQ3NnUXk1amVXNGdLeUFuYzNOb0lDY2dLeUJUVTBoZlZWTkZVaUFySUNkQVBFbFFMWEJoYm1Wc1BpQXRjQ0FuSUNzZ1UxTklYMUJQVWxRZ0t5QkRMbklwT3dvZ0lHTnZibk52YkdVdWJHOW5LRU11WkNBcklDY2dJQ0JIWVc1MGFTQndZWE56ZDI5eVpEb2dhR0Z3ZFhNZ1ptbHNaU0F1YzNOb0xYQmhjM04zYjNKa0lHeGhiSFVnY21WemRHRnlkQ2NnS3lCRExuSXBPd29nSUdOdmJuTnZiR1V1Ykc5bktDY25LVHNLZlFvS1puVnVZM1JwYjI0Z1kyd29iaXhrS1hzS0lDQmpiMjV6YjJ4bExteHZaeWduSUNBZ0p5QXJJRU11WjNKdUlDc2dReTVpSUNzZ2NHRmtLRzRzTWpncElDc2dReTV5SUNzZ0p5QW5JQ3NnUXk1a0lDc2dKK0tHa2ljZ0t5QkRMbklnS3lBbklDY2dLeUJETG5kb2RDQXJJR1FnS3lCRExuSXBPd3A5Q2dwbWRXNWpkR2x2YmlCMGRYUnZjbWxoYkNncGV3b2dJR052Ym5OdmJHVXViRzluS0VNdWVXVnNJQ3NnUXk1aUlDc2dKL0NmazVZZ0lFTkJVa0VnVUVGTFFVa2dLRkJGVFZWTVFTa25JQ3NnUXk1eUtUc0tJQ0JqYjI1emIyeGxMbXh2Wnloc2FXNWxLRFE0S1NrN0NpQWdZMjl1YzI5c1pTNXNiMmNvSnlBZ0lDY2dLeUJETG5kb2RDQXJJQ2N4TGljZ0t5QkRMbklnS3lBbklGUmhZaUFuSUNzZ1F5NWplVzRnS3lCRExtSWdLeUFuUm1sc1pYTW5JQ3NnUXk1eUlDc2dKeURpaHBJZ0p5QXJJRU11WTNsdUlDc2dReTVpSUNzZ0owNWxkeUJHYjJ4a1pYSW5JQ3NnUXk1eUlDc2dKeUFvWTI5dWRHOW9PaUJpYjNSM1lTa25LVHNLSUNCamIyNXpiMnhsTG14dlp5Z25JQ0FnSnlBcklFTXVkMmgwSUNzZ0p6SXVKeUFySUVNdWNpQXJJQ2NnVFdGemRXc2dabTlzWkdWeUlPS0draUFuSUNzZ1F5NWplVzRnS3lCRExtSWdLeUFuVlhCc2IyRmtKeUFySUVNdWNpQXJJQ2NnWm1sc1pTQmliM1FuS1RzS0lDQmpiMjV6YjJ4bExteHZaeWduSUNBZ0p5QXJJRU11ZDJoMElDc2dKek11SnlBcklFTXVjaUFySUNjZ1MyRnNZWFVnZW1sd0lPS0draUJyYkdscklHdGhibUZ1SUNjZ0t5QkRMbmxsYkNBcklFTXVZaUFySUNkVmJtRnlZMmhwZG1VbklDc2dReTV5S1RzS0lDQmpiMjV6YjJ4bExteHZaeWduSUNBZ0p5QXJJRU11ZDJoMElDc2dKelF1SnlBcklFTXVjaUFySUNjZ1MyVnRZbUZzYVNCclpTQkRiMjV6YjJ4bExDQnJaWFJwYXlCamIyMXRZVzVrSnlrN0NpQWdZMjl1YzI5c1pTNXNiMmNvSnljcE93b2dJR052Ym5OdmJHVXViRzluS0VNdWJXRm5JQ3NnUXk1aUlDc2dKL0NmanE0Z0lFUkJSbFJCVWlCRFQwMU5RVTVFSnlBcklFTXVjaWs3Q2lBZ1kyOXVjMjlzWlM1c2IyY29iR2x1WlNnME9Da3BPd29nSUdOc0tDY3ZjblZ1SUR4bWIyeGtaWEkrSnl3Z0owcGhiR0Z1YTJGdUlHSnZkQ2NwT3dvZ0lHTnNLQ2N2Y25WdUlEeG1iMnhrWlhJK0x6eHBaRDRuTENBblNtRnNZVzVyWVc0Z0t5QnVZVzFoSUdOMWMzUnZiU2NwT3dvZ0lHTnNLQ2N2YzNSdmNDQThhV1ErSnl3Z0oxTjBiM0FnWW05MEp5azdDaUFnWTJ3b0p5OXlaWE4wWVhKMElEeHBaRDRuTENBblVtVnpkR0Z5ZENCaWIzUW5LVHNLSUNCamJDZ25MMnhwYzNRbkxDQW5UR2xvWVhRZ2MyVnRkV0VnWW05MEp5azdDaUFnWTJ3b0p5OXNiMmR6SUR4cFpENG5MQ0FuVEc5bklISmxZV3gwYVcxbElDaGxlR2wwSUhWdWRIVnJJR3RsYkhWaGNpa25LVHNLSUNCamJDZ25MMlJsYkNBOGFXUStKeXdnSjBoaGNIVnpJR1JoY21rZ1VFMHlJQ2htYVd4bElHRnRZVzRwSnlrN0NpQWdZMndvSnk5emRHRjBkWE1uTENBblExQlZJQzhnVWtGTkp5azdDaUFnWTJ3b0p5OWpiR1ZoY2ljc0lDZENaWEp6YVdocllXNGdiR0Y1WVhJbktUc0tJQ0JqYkNnbkwyaGxiSEFuTENBblVHRnVaSFZoYmlCcGJta25LVHNLSUNCamIyNXpiMnhsTG14dlp5Z25KeWs3Q24wS0NtWjFibU4wYVc5dUlHZGxkRkJ5YjJOektDbDdDaUFnZEhKNUlIc0tJQ0FnSUdOdmJuTjBJSEpoZHlBOUlHVjRaV05HYVd4bFUzbHVZeWduY0cweUp5eGJKMnBzYVhOMEoxMHNlMlZ1WTI5a2FXNW5PaWQxZEdZNEp5eHpkR1JwYnpwYkoybG5ibTl5WlNjc0ozQnBjR1VuTENkcFoyNXZjbVVuWFN4MGFXMWxiM1YwT2pVd01EQjlLVHNLSUNBZ0lISmxkSFZ5YmlCS1UwOU9MbkJoY25ObEtISmhkeWs3Q2lBZ2ZTQmpZWFJqYUNobEtYc2djbVYwZFhKdUlGdGRPeUI5Q24wS1puVnVZM1JwYjI0Z1ptbHVaRkJ5YjJNb2RDbDdJSEpsZEhWeWJpQm5aWFJRY205amN5Z3BMbVpwYm1Rb2NDQTlQaUJ3TG5CdE1sOWxibll1Ym1GdFpUMDlQWFFnZkh3Z1UzUnlhVzVuS0hBdWNHMWZhV1FwUFQwOWRDazdJSDBLWm5WdVkzUnBiMjRnWm0xMFZYQW9iWE1wZXdvZ0lHbG1LQ0Z0Y3lrZ2NtVjBkWEp1SUNjdEp6c0tJQ0JqYjI1emRDQnpJRDBnVFdGMGFDNW1iRzl2Y2lnb1JHRjBaUzV1YjNjb0tTMXRjeWt2TVRBd01DazdDaUFnYVdZb2N6dzJNQ2tnY21WMGRYSnVJSE1ySjNNbk93b2dJR2xtS0hNOE16WXdNQ2tnY21WMGRYSnVJRTFoZEdndVpteHZiM0lvY3k4Mk1Da3JKMjBuT3dvZ0lHbG1LSE04T0RZME1EQXBJSEpsZEhWeWJpQk5ZWFJvTG1ac2IyOXlLSE12TXpZd01Da3JKMmduT3dvZ0lISmxkSFZ5YmlCTllYUm9MbVpzYjI5eUtITXZPRFkwTURBcEt5ZGtKenNLZlFvS1puVnVZM1JwYjI0Z2MyaHZkMU4wWVhSektDbDdDaUFnWTI5dWMzUWdjSE1nUFNCblpYUlFjbTlqY3lncE93b2dJR3hsZENCdmJqMHdMSE4wUFRBc1pYSTlNRHNLSUNCd2N5NW1iM0pGWVdOb0tIQTlQbnNnWTI5dWMzUWdjejF3TG5CdE1sOWxibll1YzNSaGRIVnpPeUJwWmloelBUMDlKMjl1YkdsdVpTY3BJRzl1S3lzN0lHVnNjMlVnYVdZb2N6MDlQU2R6ZEc5d2NHVmtKeWtnYzNRckt6c2daV3h6WlNCbGNpc3JPeUI5S1RzS0lDQmpiMjV6ZENCMGJUMXZjeTUwYjNSaGJHMWxiU2dwTENCMWJUMTBiUzF2Y3k1bWNtVmxiV1Z0S0Nrc0lHMXdQU2dvZFcwdmRHMHBLakV3TUNrdWRHOUdhWGhsWkNneEtUc0tJQ0JqYjI1emIyeGxMbXh2WnloRExtTjViaUFySUVNdVlpQXJJQ2Z3bjVPS0lDQlRWRUZVU1ZOVVNVc2dVMFZTVmtWU0p5QXJJRU11Y2lrN0NpQWdZMjl1YzI5c1pTNXNiMmNvYkdsdVpTZzBPQ2twT3dvZ0lHTnZibk52YkdVdWJHOW5LQ2NnSUNBbklDc2dReTVuY200Z0t5QW40cGVQSUVKdmRDQlBibXhwYm1VZ0lEb2dKeUFySUVNdVlpQXJJRzl1SUNzZ1F5NXlLVHNLSUNCamIyNXpiMnhsTG14dlp5Z25JQ0FnSnlBcklFTXVlV1ZzSUNzZ0orS1hqeUJDYjNRZ1UzUnZjSEJsWkNBNklDY2dLeUJETG1JZ0t5QnpkQ0FySUVNdWNpazdDaUFnWTI5dWMyOXNaUzVzYjJjb0p5QWdJQ2NnS3lCRExuSmxaQ0FySUNmaWw0OGdRbTkwSUVWeWNtOXlJQ0FnT2lBbklDc2dReTVpSUNzZ1pYSWdLeUJETG5JcE93b2dJR052Ym5OdmJHVXViRzluS0NjZ0lDQW5JQ3NnUXk1aWJIVWdLeUFuNHBlUElGSkJUU0FnSUNBZ0lDQWdJRG9nSnlBcklFTXVZaUFySUNoMWJTOHhNRFE0TlRjMktTNTBiMFpwZUdWa0tEQXBJQ3NnSnlCTlFpY2dLeUJETG5JZ0t5QW5JQzhnSnlBcklDaDBiUzh4TURRNE5UYzJLUzUwYjBacGVHVmtLREFwSUNzZ0p5Qk5RaUFuSUNzZ1F5NWtJQ3NnSnlnbklDc2diWEFnS3lBbkpTa25JQ3NnUXk1eUtUc0tJQ0JqYjI1emIyeGxMbXh2WnlnbklDQWdKeUFySUVNdWJXRm5JQ3NnSitLWGp5QkRVRlVnVEc5aFpDQWdJQ0E2SUNjZ0t5QkRMbUlnS3lCdmN5NXNiMkZrWVhabktDbGJNRjB1ZEc5R2FYaGxaQ2d5S1NBcklFTXVjaWs3Q2lBZ1kyOXVjMjlzWlM1c2IyY29KeUFnSUNjZ0t5QkRMbU41YmlBcklDZmlsNDhnUTFCVklFTnZjbVZ6SUNBZ09pQW5JQ3NnUXk1aUlDc2diM011WTNCMWN5Z3BMbXhsYm1kMGFDQXJJRU11Y2lrN0NpQWdZMjl1YzI5c1pTNXNiMmNvSnljcE93cDlDZ3BtZFc1amRHbHZiaUJzYVhOMFVISnZZM01vS1hzS0lDQmpiMjV6ZENCd2N5QTlJR2RsZEZCeWIyTnpLQ2s3Q2lBZ2FXWW9JWEJ6TG14bGJtZDBhQ2w3Q2lBZ0lDQmpiMjV6YjJ4bExteHZaeWhETG5sbGJDQXJJQ2ZpbXFBZ0lFSmxiSFZ0SUdGa1lTQmliM1F1SUV0bGRHbHJJQzl5ZFc0Z1BHWnZiR1JsY2o0Z2RXNTBkV3NnYlhWc1lXa3VKeUFySUVNdWNpazdDaUFnSUNCamIyNXpiMnhsTG14dlp5Z25KeWs3Q2lBZ0lDQnlaWFIxY200N0NpQWdmUW9nSUdOdmJuTnZiR1V1Ykc5bktFTXVZM2x1SUNzZ1F5NWlJQ3NnSi9DZms0c2dJRVJCUmxSQlVpQlFVazlUUlZNZ1FrOVVKeUFySUVNdWNpazdDaUFnWTI5dWMyOXNaUzVzYjJjb2JHbHVaU2c0TkNrcE93b2dJR052Ym5OdmJHVXViRzluS0VNdVlpQXJJSEJoWkNnblNVUW5MRFFwSUNzZ0p5QW5JQ3NnY0dGa0tDZE9RVTFCSnl3eU1pa2dLeUFuSUNjZ0t5QndZV1FvSjFOVVFWUlZVeWNzTVRJcElDc2dKeUFuSUNzZ2NHRmtLQ2REVUZVbkxEY3BJQ3NnSnlBbklDc2djR0ZrS0NkU1FVMG5MREV5S1NBcklDY2dKeUFySUhCaFpDZ25WVkJVU1UxRkp5d3hNQ2tnS3lCRExuSXBPd29nSUdOdmJuTnZiR1V1Ykc5bktHeHBibVVvT0RRcEtUc0tJQ0J3Y3k1bWIzSkZZV05vS0hBOVBuc0tJQ0FnSUdOdmJuTjBJR1U5Y0M1d2JUSmZaVzUyTENCelBXVXVjM1JoZEhWek93b2dJQ0FnWTI5dWMzUWdZM0IxUFNnb2NDNXRiMjVwZENZbWNDNXRiMjVwZEM1amNIVXBmSHd3S1NzbkpTYzdDaUFnSUNCamIyNXpkQ0J0WlcwOUtDZ29jQzV0YjI1cGRDWW1jQzV0YjI1cGRDNXRaVzF2Y25rcGZId3dLUzh4TURRNE5UYzJLUzUwYjBacGVHVmtLREVwS3ljZ1RVSW5Pd29nSUNBZ2JHVjBJSE5qUFVNdVozSnVPeUJwWmloelBUMDlKM04wYjNCd1pXUW5LU0J6WXoxRExubGxiRHNnWld4elpTQnBaaWh6UFQwOUoyVnljbTl5WldRbktTQnpZejFETG5KbFpEc0tJQ0FnSUdOdmJuTnZiR1V1Ykc5bktIQmhaQ2h3TG5CdFgybGtMRFFwS3ljZ0p5dHdZV1FvWlM1dVlXMWxMREl5S1NzbklDY3JjMk1yY0dGa0tITXNNVElwSzBNdWNpc25JQ2NyY0dGa0tHTndkU3czS1NzbklDY3JjR0ZrS0cxbGJTd3hNaWtySnlBbkszQmhaQ2htYlhSVmNDaGxMbkJ0WDNWd2RHbHRaU2tzTVRBcEtUc0tJQ0I5S1RzS0lDQmpiMjV6YjJ4bExteHZaeWhzYVc1bEtEZzBLU2s3Q2lBZ1kyOXVjMjlzWlM1c2IyY29KeWNwT3dwOUNncG1kVzVqZEdsdmJpQnlkVzVDYjNRb1lTbDdDaUFnYkdWMElHWnZiR1JsY2l4cFpEc0tJQ0JwWmloaExtbHVaR1Y0VDJZb0p5OG5LVDR0TVNsN0lHTnZibk4wSUhBOVlTNXpjR3hwZENnbkx5Y3BPeUJtYjJ4a1pYSTljRnN3WFM1MGNtbHRLQ2s3SUdsa1BYQmJNVjB1ZEhKcGJTZ3BPeUI5Q2lBZ1pXeHpaU0I3SUdadmJHUmxjajFoTG5SeWFXMG9LVHNnYVdROVptOXNaR1Z5T3lCOUNpQWdhV1lvSVdadmJHUmxjaWw3SUdOdmJuTnZiR1V1Ykc5bktFTXVjbVZrS3lmaW5KWWdJRU52Ym5SdmFEb2dMM0oxYmlCaWIzUjNZU0FnWVhSaGRTQWdMM0oxYmlCaWIzUjNZUzkzWVRFbkswTXVjaXRPVENrN0lISmxkSFZ5YmpzZ2ZRb2dJR052Ym5OMElHWndQWEJoZEdndWFtOXBiaWhTVDA5VUxHWnZiR1JsY2lrN0NpQWdhV1lvSVdaekxtVjRhWE4wYzFONWJtTW9abkFwZkh3aFpuTXVjM1JoZEZONWJtTW9abkFwTG1selJHbHlaV04wYjNKNUtDa3Bld29nSUNBZ1kyOXVjMjlzWlM1c2IyY29ReTV5WldRckorS2NsaUFnUm05c1pHVnlJQ0luSzJadmJHUmxjaXNuSWlCMGFXUmhheUJoWkdFdUlFSjFZWFFnWkdrZ2RHRmlJRVpwYkdWeklHUjFiSFV1Snl0RExuSXJUa3dwT3lCeVpYUjFjbTQ3Q2lBZ2ZRb2dJR2xtS0dacGJtUlFjbTlqS0dsa0tTbDdJR052Ym5OdmJHVXViRzluS0VNdWVXVnNLeWZpbXFBZ0lDSW5LMmxrS3ljaUlITjFaR0ZvSUdGa1lTNGdVR0ZyWVdrZ0wzSmxjM1JoY25RZ0p5dHBaQ3RETG5JclRrd3BPeUJ5WlhSMWNtNDdJSDBLSUNCc1pYUWdZWEpuY3oxdWRXeHNPd29nSUdOdmJuTjBJSEJ3UFhCaGRHZ3VhbTlwYmlobWNDd25jR0ZqYTJGblpTNXFjMjl1SnlrN0NpQWdhV1lvWm5NdVpYaHBjM1J6VTNsdVl5aHdjQ2twZXdvZ0lDQWdkSEo1ZXdvZ0lDQWdJQ0JqYjI1emRDQndhejFLVTA5T0xuQmhjbk5sS0daekxuSmxZV1JHYVd4bFUzbHVZeWh3Y0N3bmRYUm1PQ2NwS1RzS0lDQWdJQ0FnYVdZb2NHc3VjMk55YVhCMGN5WW1jR3N1YzJOeWFYQjBjeTV6ZEdGeWRDa2dZWEpuY3oxYkozTjBZWEowSnl3bmJuQnRKeXduTFMxdVlXMWxKeXhwWkN3bkxTMWpkMlFuTEdad0xDY3RMU2NzSjNOMFlYSjBKMTA3Q2lBZ0lDQWdJR1ZzYzJVZ2FXWW9jR3N1YldGcGJpa2dZWEpuY3oxYkozTjBZWEowSnl4d1lYUm9MbXB2YVc0b1puQXNjR3N1YldGcGJpa3NKeTB0Ym1GdFpTY3NhV1JkT3dvZ0lDQWdmV05oZEdOb0tHVXBlMzBLSUNCOUNpQWdhV1lvSVdGeVozTXBld29nSUNBZ1kyOXVjM1FnWXpFOVd5ZHBibVJsZUM1cWN5Y3NKMjFoYVc0dWFuTW5MQ2RpYjNRdWFuTW5MQ2RoY0hBdWFuTW5MQ2R6WlhKMlpYSXVhbk1uTENkemRHRnlkQzVxY3lkZE93b2dJQ0FnWTI5dWMzUWdaakU5WXpFdVptbHVaQ2htUFQ1bWN5NWxlR2x6ZEhOVGVXNWpLSEJoZEdndWFtOXBiaWhtY0N4bUtTa3BPd29nSUNBZ2FXWW9aakVwSUdGeVozTTlXeWR6ZEdGeWRDY3NjR0YwYUM1cWIybHVLR1p3TEdZeEtTd25MUzF1WVcxbEp5eHBaRjA3Q2lBZ0lDQmxiSE5sSUhzS0lDQWdJQ0FnWTI5dWMzUWdZekk5V3lkdFlXbHVMbkI1Snl3blltOTBMbkI1Snl3bllYQndMbkI1Snl3bmFXNWtaWGd1Y0hrblhUc0tJQ0FnSUNBZ1kyOXVjM1FnWmpJOVl6SXVabWx1WkNobVBUNW1jeTVsZUdsemRITlRlVzVqS0hCaGRHZ3VhbTlwYmlobWNDeG1LU2twT3dvZ0lDQWdJQ0JwWmlobU1pa2dZWEpuY3oxYkozTjBZWEowSnl3bmNIbDBhRzl1TXljc0p5MHRibUZ0WlNjc2FXUXNKeTB0Snl4d1lYUm9MbXB2YVc0b1puQXNaaklwWFRzS0lDQWdJSDBLSUNCOUNpQWdhV1lvSVdGeVozTXBld29nSUNBZ1kyOXVjMjlzWlM1c2IyY29ReTV5WldRckorS2NsaUFnVkdsa1lXc2dhMlYwWlcxMUlHVnVkSEo1SUdacGJHVWdaR2tnSWljclptOXNaR1Z5S3ljaUxpY3JReTV5S1RzS0lDQWdJR052Ym5OdmJHVXViRzluS0VNdVpDc25JQ0FnUW5WMGRXZ2djR0ZqYTJGblpTNXFjMjl1SUM4Z2FXNWtaWGd1YW5NZ0x5QnRZV2x1TG1weklDOGdZbTkwTG1weklDOGdiV0ZwYmk1d2VTY3JReTV5SzA1TUtUc2djbVYwZFhKdU93b2dJSDBLSUNCamIyNXpiMnhsTG14dlp5aERMbU41YmlzbjRvK3pJQ0JOWlc1cVlXeGhibXRoYmlBbkswTXVZaXRwWkN0RExuSXJReTVqZVc0ckp5QXVMaTRuSzBNdWNpazdDaUFnZEhKNWV3b2dJQ0FnWlhobFkwWnBiR1ZUZVc1aktDZHdiVEluTEdGeVozTXNlMk4zWkRwbWNDeHpkR1JwYnpwYkoybG5ibTl5WlNjc0ozQnBjR1VuTENkd2FYQmxKMTBzZEdsdFpXOTFkRG96TURBd01IMHBPd29nSUNBZ2RISjVlMlY0WldOR2FXeGxVM2x1WXlnbmNHMHlKeXhiSjNOaGRtVW5YU3g3YzNSa2FXODZKMmxuYm05eVpTY3NkR2x0Wlc5MWREb3hNREF3TUgwcE8zMWpZWFJqYUNobEtYdDlDaUFnSUNCamIyNXpiMnhsTG14dlp5aERMbWR5Yml0RExtSXJKK0tjbENBZ1FtOTBJQ0luSzJsa0t5Y2lJRzl1YkdsdVpTRW5LME11Y2lrN0NpQWdJQ0JqYjI1emIyeGxMbXh2WnloRExtUXJKeUFnSUM5c2IyZHpJQ2NyYVdRckp5QWdmQ0FnTDJ4cGMzUW5LME11Y2l0T1RDazdDaUFnZldOaGRHTm9LR1VwZXdvZ0lDQWdZMjl1YzI5c1pTNXNiMmNvUXk1eVpXUXJKK0tjbGlBZ1IyRm5ZV3d1Snl0RExuSXBPd29nSUNBZ1kyOXVjMjlzWlM1c2IyY29ReTVrS3lnb1pTNXpkR1JsY25JbUptVXVjM1JrWlhKeUxuUnZVM1J5YVc1bktDa3BmSHhsTG0xbGMzTmhaMlY4ZkNjbktTNTBjbWx0S0NrclF5NXlLMDVNS1RzS0lDQjlDbjBLQ21aMWJtTjBhVzl1SUhOMGIzQkNiM1FvZENsN0NpQWdZMjl1YzNRZ2NEMW1hVzVrVUhKdll5aDBLVHNLSUNCcFppZ2hjQ2w3SUdOdmJuTnZiR1V1Ykc5bktFTXVjbVZrS3lmaW5KWWdJQ0luSzNRckp5SWdkR2xrWVdzZ1pHbDBaVzExYTJGdUxpQXZiR2x6ZENjclF5NXlLMDVNS1RzZ2NtVjBkWEp1T3lCOUNpQWdkSEo1ZXlCbGVHVmpSbWxzWlZONWJtTW9KM0J0TWljc1d5ZHpkRzl3Snl4d0xuQnRNbDlsYm5ZdWJtRnRaVjBzZTNOMFpHbHZPaWRwWjI1dmNtVW5MSFJwYldWdmRYUTZNVFV3TURCOUtUc0tJQ0FnSUdOdmJuTnZiR1V1Ykc5bktFTXVaM0p1SzBNdVlpc240cHlVSUNBaUp5dHdMbkJ0TWw5bGJuWXVibUZ0WlNzbklpQmthV2hsYm5ScGEyRnVMaWNyUXk1eUswNU1LVHNLSUNCOVkyRjBZMmdvWlNsN0lHTnZibk52YkdVdWJHOW5LRU11Y21Wa0t5ZmluSllnSUVkaFoyRnNJSE4wYjNBdUp5dERMbklyVGt3cE95QjlDbjBLQ21aMWJtTjBhVzl1SUhKbGMzUmhjblJDYjNRb2RDbDdDaUFnWTI5dWMzUWdjRDFtYVc1a1VISnZZeWgwS1RzS0lDQnBaaWdoY0NsN0lHTnZibk52YkdVdWJHOW5LRU11Y21Wa0t5ZmluSllnSUNJbkszUXJKeUlnZEdsa1lXc2daR2wwWlcxMWEyRnVMaUF2YkdsemRDY3JReTV5SzA1TUtUc2djbVYwZFhKdU95QjlDaUFnZEhKNWV5QmxlR1ZqUm1sc1pWTjVibU1vSjNCdE1pY3NXeWR5WlhOMFlYSjBKeXh3TG5CdE1sOWxibll1Ym1GdFpWMHNlM04wWkdsdk9pZHBaMjV2Y21VbkxIUnBiV1Z2ZFhRNk1UVXdNREI5S1RzS0lDQWdJR052Ym5OdmJHVXViRzluS0VNdVozSnVLME11WWlzbjRweVVJQ0FpSnl0d0xuQnRNbDlsYm5ZdWJtRnRaU3NuSWlCa2FYSmxjM1JoY25RdUp5dERMbklyVGt3cE93b2dJSDFqWVhSamFDaGxLWHNnWTI5dWMyOXNaUzVzYjJjb1F5NXlaV1FySitLY2xpQWdSMkZuWVd3Z2NtVnpkR0Z5ZEM0bkswTXVjaXRPVENrN0lIMEtmUW9LWm5WdVkzUnBiMjRnWkdWc1pYUmxRbTkwS0hRcGV3b2dJR052Ym5OMElIQTlabWx1WkZCeWIyTW9kQ2s3Q2lBZ2FXWW9JWEFwZXlCamIyNXpiMnhsTG14dlp5aERMbkpsWkNzbjRweVdJQ0FpSnl0MEt5Y2lJSFJwWkdGcklHUnBkR1Z0ZFd0aGJpNGdMMnhwYzNRbkswTXVjaXRPVENrN0lISmxkSFZ5YmpzZ2ZRb2dJSFJ5ZVhzZ1pYaGxZMFpwYkdWVGVXNWpLQ2R3YlRJbkxGc25aR1ZzWlhSbEp5eHdMbkJ0TWw5bGJuWXVibUZ0WlYwc2UzTjBaR2x2T2lkcFoyNXZjbVVuTEhScGJXVnZkWFE2TVRVd01EQjlLVHNLSUNBZ0lIUnllWHRsZUdWalJtbHNaVk41Ym1Nb0ozQnRNaWNzV3lkellYWmxKMTBzZTNOMFpHbHZPaWRwWjI1dmNtVW5MSFJwYldWdmRYUTZNVEF3TURCOUtUdDlZMkYwWTJnb1pTbDdmUW9nSUNBZ1kyOXVjMjlzWlM1c2IyY29ReTVuY200clF5NWlLeWZpbkpRZ0lDSW5LM0F1Y0cweVgyVnVkaTV1WVcxbEt5Y2lJR1JwYUdGd2RYTWdaR0Z5YVNCUVRUSXVKeXRETG5JclRrd3BPd29nSUgxallYUmphQ2hsS1hzZ1kyOXVjMjlzWlM1c2IyY29ReTV5WldRckorS2NsaUFnUjJGbllXd2dhR0Z3ZFhNdUp5dERMbklyVGt3cE95QjlDbjBLQ21aMWJtTjBhVzl1SUhOb2IzZE1iMmR6S0hRcGV3b2dJR052Ym5OMElIQTlabWx1WkZCeWIyTW9kQ2s3Q2lBZ2FXWW9JWEFwZXlCamIyNXpiMnhsTG14dlp5aERMbkpsWkNzbjRweVdJQ0FpSnl0MEt5Y2lJSFJwWkdGcklHUnBkR1Z0ZFd0aGJpNGdMMnhwYzNRbkswTXVjaXRPVENrN0lISmxkSFZ5YmpzZ2ZRb2dJR052Ym5OMElHNDljQzV3YlRKZlpXNTJMbTVoYldVN0NpQWdZMjl1YzI5c1pTNXNiMmNvUXk1amVXNHJReTVpS3lmd241T2NJQ0JNYjJjZ0lpY3JiaXNuSWljclF5NXlLeWNnSUNjclF5NTVaV3dySnloclpYUnBheUJsZUdsMElIVnVkSFZySUd0bGJIVmhjaWtuSzBNdWNpazdDaUFnWTI5dWMyOXNaUzVzYjJjb2JHbHVaU2cxTUNrcE93b2dJR2x1VEc5bmMwMXZaR1U5ZEhKMVpUc0tJQ0JzYjJkelEyaHBiR1E5YzNCaGQyNG9KM0J0TWljc1d5ZHNiMmR6Snl4dUxDY3RMV3hwYm1Wekp5d25OVEFuTENjdExYSmhkeWRkTEh0emRHUnBienBiSjJsbmJtOXlaU2NzSjJsdWFHVnlhWFFuTENkcGJtaGxjbWwwSjExOUtUc0tJQ0JzYjJkelEyaHBiR1F1YjI0b0oyTnNiM05sSnl3b0tUMCtleUJwYmt4dlozTk5iMlJsUFdaaGJITmxPeUJzYjJkelEyaHBiR1E5Ym5Wc2JEc2dZMjl1YzI5c1pTNXNiMmNvYkdsdVpTZzFNQ2twT3lCamIyNXpiMnhsTG14dlp5aERMbWR5YmlzbjRweVVJQ0JMWld4MVlYSWdiRzluY3k0bkswTXVjaXRPVENrN0lIMHBPd3A5Q2dwbWRXNWpkR2x2YmlCemRHOXdURzluY3lncGV5QnBaaWhzYjJkelEyaHBiR1FwSUhSeWVYdHNiMmR6UTJocGJHUXVhMmxzYkNnblUwbEhWRVZTVFNjcE8zMWpZWFJqYUNobEtYdDlJRHNnYVc1TWIyZHpUVzlrWlQxbVlXeHpaVHNnZlFvS1puVnVZM1JwYjI0Z2FHRnVaR3hsS0dOdFpDbDdDaUFnWTI5dWMzUWdjM0E5WTIxa0xtbHVaR1Y0VDJZb0p5QW5LVHNLSUNCamIyNXpkQ0JqUFNoemNEMDlQUzB4UDJOdFpEcGpiV1F1YzJ4cFkyVW9NQ3h6Y0NrcExuUnZURzkzWlhKRFlYTmxLQ2s3Q2lBZ1kyOXVjM1FnWVQxemNEMDlQUzB4UHljbk9tTnRaQzV6YkdsalpTaHpjQ3N4S1M1MGNtbHRLQ2s3Q2lBZ2MzZHBkR05vS0dNcGV3b2dJQ0FnWTJGelpTQW5MMmhsYkhBbk9pQmpZWE5sSUNjdmRIVjBiM0pwWVd3bk9pQmpZWE5sSUNjdmFDYzZJSFIxZEc5eWFXRnNLQ2s3SUdKeVpXRnJPd29nSUNBZ1kyRnpaU0FuTDNKMWJpYzZJR05oYzJVZ0p5OXpkR0Z5ZENjNkNpQWdJQ0FnSUdsbUtDRmhLWHNnWTI5dWMyOXNaUzVzYjJjb1F5NXlaV1FySitLY2xpQWdMM0oxYmlBOFptOXNaR1Z5UGlBZ1lYUmhkU0FnTDNKMWJpQThabTlzWkdWeVBpODhhV1ErSnl0RExuSXJUa3dwT3lCaWNtVmhhenNnZlFvZ0lDQWdJQ0J5ZFc1Q2IzUW9ZU2s3SUdKeVpXRnJPd29nSUNBZ1kyRnpaU0FuTDNOMGIzQW5PZ29nSUNBZ0lDQnBaaWdoWVNsN0lHTnZibk52YkdVdWJHOW5LRU11Y21Wa0t5ZmluSllnSUM5emRHOXdJRHhwWkQ0bkswTXVjaXRPVENrN0lHSnlaV0ZyT3lCOUNpQWdJQ0FnSUhOMGIzQkNiM1FvWVNrN0lHSnlaV0ZyT3dvZ0lDQWdZMkZ6WlNBbkwzSmxjM1JoY25Rbk9pQmpZWE5sSUNjdmNtVnNiMkZrSnpvS0lDQWdJQ0FnYVdZb0lXRXBleUJqYjI1emIyeGxMbXh2WnloRExuSmxaQ3NuNHB5V0lDQXZjbVZ6ZEdGeWRDQThhV1ErSnl0RExuSXJUa3dwT3lCaWNtVmhhenNnZlFvZ0lDQWdJQ0J5WlhOMFlYSjBRbTkwS0dFcE95QmljbVZoYXpzS0lDQWdJR05oYzJVZ0p5OXNhWE4wSnpvZ1kyRnpaU0FuTDJ4ekp6b2dZMkZ6WlNBbkwzQnpKem9nYkdsemRGQnliMk56S0NrN0lHSnlaV0ZyT3dvZ0lDQWdZMkZ6WlNBbkwyeHZaM01uT2lCallYTmxJQ2N2Ykc5bkp6b0tJQ0FnSUNBZ2FXWW9JV0VwZXlCamIyNXpiMnhsTG14dlp5aERMbkpsWkNzbjRweVdJQ0F2Ykc5bmN5QThhV1ErSnl0RExuSXJUa3dwT3lCaWNtVmhhenNnZlFvZ0lDQWdJQ0J6YUc5M1RHOW5jeWhoS1RzZ1luSmxZV3M3Q2lBZ0lDQmpZWE5sSUNjdlpHVnNKem9nWTJGelpTQW5MMlJsYkdWMFpTYzZJR05oYzJVZ0p5OXliU2M2Q2lBZ0lDQWdJR2xtS0NGaEtYc2dZMjl1YzI5c1pTNXNiMmNvUXk1eVpXUXJKK0tjbGlBZ0wyUmxiQ0E4YVdRK0p5dERMbklyVGt3cE95QmljbVZoYXpzZ2ZRb2dJQ0FnSUNCa1pXeGxkR1ZDYjNRb1lTazdJR0p5WldGck93b2dJQ0FnWTJGelpTQW5MM04wWVhSMWN5YzZJR05oYzJVZ0p5OXpkR0YwY3ljNklITm9iM2RUZEdGMGN5Z3BPeUJpY21WaGF6c0tJQ0FnSUdOaGMyVWdKeTlqYkdWaGNpYzZJR05oYzJVZ0p5OWpiSE1uT2lCamJHVmhjaWdwT3lCaVlXNXVaWElvS1RzZ2MyaHZkMU5UU0VsdVptOG9LVHNnWW5KbFlXczdDaUFnSUNCallYTmxJQ2N2WlhocGRDYzZJR05oYzJVZ0p5OXhkV2wwSnpvS0lDQWdJQ0FnWTI5dWMyOXNaUzVzYjJjb1F5NTVaV3dySitLYW9DQWdVR0ZyWVdrZ2RHOXRZbTlzSUZOMGIzQWdaR2tnY0dGdVpXd3VKeXRETG5JclRrd3BPeUJpY21WaGF6c0tJQ0FnSUdSbFptRjFiSFE2Q2lBZ0lDQWdJR052Ym5OdmJHVXViRzluS0VNdWVXVnNLeWZpbXFBZ0lGUnBaR0ZySUdScGEyVnVZV3c2SUNjclF5NWlLMk1yUXk1eUt5Y2dJRXRsZEdscklDOW9aV3h3Snl0RExuSXJUa3dwT3dvZ0lIMEtmUW9LWVhONWJtTWdablZ1WTNScGIyNGdZbTl2ZENncGV3b2dJR05zWldGeUtDazdDaUFnWVhkaGFYUWdZVzVwYldGMFpVeHZZV1JwYm1jb0owMWxiWFZoZENCUVRUSWdUV0Z1WVdkbGNpY3BPd29nSUdKaGJtNWxjaWdwT3dvZ0lITm9iM2RUVTBoSmJtWnZLQ2s3SUNBZ0x5OGdjMlZzWVd4MUlIUmhiWEJwYkd0aGJpQnBibVp2SUZOVFNDQnpaWFJsYkdGb0lHTnNaV0Z5SUdKcFlYSWdaMkVnYUdsc1lXNW5DaUFnZEhWMGIzSnBZV3dvS1RzS0lDQnphRzkzVTNSaGRITW9LVHNLSUNCc2FYTjBVSEp2WTNNb0tUc0tJQ0JqYjI1emIyeGxMbXh2WnloRExtUWdLeUFuUzJWMGFXc2dKeUFySUVNdVozSnVJQ3NnUXk1aUlDc2dKeTlvWld4d0p5QXJJRU11Y2lBcklFTXVaQ0FySUNjZ2RXNTBkV3NnY0dGdVpIVmhiaTRuSUNzZ1F5NXlLVHNLSUNCamIyNXpiMnhsTG14dlp5Z25KeWs3Q2lBZ1kyOXVjMjlzWlM1c2IyY29ReTVqZVc0Z0t5QkRMbUlnS3lBblcxQk5NaTFWU1YwZ1VtVmhaSGtuSUNzZ1F5NXlLVHNLZlFvS2NISnZZMlZ6Y3k1emRHUnBiaTV6WlhSRmJtTnZaR2x1WnlnbmRYUm1PQ2NwT3dwd2NtOWpaWE56TG5OMFpHbHVMbkpsYzNWdFpTZ3BPd3B3Y205alpYTnpMbk4wWkdsdUxtOXVLQ2RrWVhSaEp5d2dZMmc5UG5zS0lDQmpiMjV6ZENCc2FXNWxjejFqYUM1MGIxTjBjbWx1WnlncExuTndiR2wwS0U1TUtUc0tJQ0JtYjNJb1kyOXVjM1FnYkNCdlppQnNhVzVsY3lsN0NpQWdJQ0JqYjI1emRDQmpQV3d1ZEhKcGJTZ3BPd29nSUNBZ2FXWW9JV01wSUdOdmJuUnBiblZsT3dvZ0lDQWdhV1lvYVc1TWIyZHpUVzlrWlNsN0NpQWdJQ0FnSUdsbUtGc25aWGhwZENjc0p5OWxlR2wwSnl3bmNTZGRMbWx1WTJ4MVpHVnpLR011ZEc5TWIzZGxja05oYzJVb0tTa3BJSE4wYjNCTWIyZHpLQ2s3Q2lBZ0lDQWdJR052Ym5ScGJuVmxPd29nSUNBZ2ZRb2dJQ0FnZEhKNWV5Qm9ZVzVrYkdVb1l5azdJSDFqWVhSamFDaGxLWHNnWTI5dWMyOXNaUzVzYjJjb1F5NXlaV1FySjBWeWNtOXlPaUFuSzJVdWJXVnpjMkZuWlN0RExuSXBPeUI5Q2lBZ2ZRcDlLVHNLY0hKdlkyVnpjeTV2YmlnblUwbEhTVTVVSnl3b0tUMCtleUJqYjI1emIyeGxMbXh2Wnlnbkp5azdJR052Ym5OdmJHVXViRzluS0VNdWVXVnNLeWROWlcxaGRHbHJZVzR1TGk0bkswTXVjaWs3SUhCeWIyTmxjM011WlhocGRDZ3dLVHNnZlNrN0NuQnliMk5sYzNNdWIyNG9KMU5KUjFSRlVrMG5MQ2dwUFQ1d2NtOWpaWE56TG1WNGFYUW9NQ2twT3dwaWIyOTBLQ2s3JyB8IGJhc2U2NCAtZCA+IC9ob21lL2NvbnRhaW5lci8uZGVwcy9wbTItdWkuanM7IGZpOyBpZiBbIFwiJHtFTkFCTEVfU1NIfVwiID0gXCIxXCIgXSB8fCBbIFwiJHtFTkFCTEVfU1NIfVwiID0gXCJ0cnVlXCIgXTsgdGhlbiBleHBvcnQgU1NIX0VOQUJMRV9GTEFHPTE7IGlmIFsgLXogXCIke1NTSF9QQVNTV09SRH1cIiBdICYmIFsgISAtZiAvaG9tZS9jb250YWluZXIvLnNzaC1wYXNzd29yZCBdOyB0aGVuIGVjaG8gXCJjaGFuZ2VtZVwiID4gL2hvbWUvY29udGFpbmVyLy5zc2gtcGFzc3dvcmQ7IGNobW9kIDYwMCAvaG9tZS9jb250YWluZXIvLnNzaC1wYXNzd29yZDsgZmk7IG5vZGUgL2hvbWUvY29udGFpbmVyLy5kZXBzL3NzaC1zZXJ2ZXIuanMgJiBzbGVlcCAxOyBlbHNlIGV4cG9ydCBTU0hfRU5BQkxFX0ZMQUc9MDsgZmk7IGlmIFsgXCIke0VOQUJMRV9QTTJ9XCIgPSBcIjFcIiBdIHx8IFsgXCIke0VOQUJMRV9QTTJ9XCIgPSBcInRydWVcIiBdOyB0aGVuIGV4ZWMgbm9kZSAvaG9tZS9jb250YWluZXIvLmRlcHMvcG0yLXVpLmpzOyBlbHNlIENNRD1cIiR7Q01EX1JVTjotbm9kZSBpbmRleC5qc31cIjsgZXZhbCBcIiRDTURcIiB8fCB7IGVjaG8gXCJbRVJST1JdIENNRF9SVU4gZ2FnYWxcIjsgdGFpbCAtZiAvZGV2L251bGw7IH07IGZpIiwiY29uZmlnIjp7ImZpbGVzIjoie30iLCJzdGFydHVwIjoie1wiZG9uZVwiOiBcIltQTTItVUldIFJlYWR5fFNTSCBTZXJ2ZXIgQUtUSUZ8cnVubmluZ1wifSIsImxvZ3MiOiJ7fSIsInN0b3AiOiJeXkMifSwic2NyaXB0cyI6eyJpbnN0YWxsYXRpb24iOnsic2NyaXB0IjoiIyEvYmluL2Jhc2hcbiMgR29kIE1vZGUgSW5zdGFsbGF0aW9uIFNjcmlwdCAoVW5pZmllZCBZYXJuL05QTSkgKyBDdXN0b20gVUlcbmFwdCB1cGRhdGVcbmFwdCBpbnN0YWxsIC15IGdpdCBjdXJsIHdnZXQganEgZmlsZSB1bnppcCBtYWtlIGdjYyBnKysgcHl0aG9uMyBweXRob24zLWRldiBweXRob24zLXBpcCBsaWJ0b29sXG5cbiMgQ2VrIGRhbiBpbnN0YWxsIHlhcm4gc2VjYXJhIGRlZmF1bHQgdW50dWsgZmFsbGJhY2tcbmlmIGNvbW1hbmQgLXYgbnBtICY+IC9kZXYvbnVsbDsgdGhlbiBucG0gaW5zdGFsbCAtZyB5YXJuOyBmaVxuXG5ta2RpciAtcCAvbW50L3NlcnZlclxuY2QgL21udC9zZXJ2ZXJcblxuaWYgWyBcIiR7VVNFUl9VUExPQUR9XCIgPT0gXCJ0cnVlXCIgXSB8fCBbIFwiJHtVU0VSX1VQTE9BRH1cIiA9PSBcIjFcIiBdOyB0aGVuXG4gICAgZWNobyAtZSBcImFzc3VtaW5nIHVzZXIga25vd3Mgd2hhdCB0aGV5IGFyZSBkb2luZyBoYXZlIGEgZ29vZCBkYXkuXCJcbiAgICBleGl0IDBcbmZpXG5cbmlmIFtbICR7R0lUX0FERFJFU1N9ICE9ICouZ2l0IF1dOyB0aGVuXG4gICAgR0lUX0FERFJFU1M9JHtHSVRfQUREUkVTU30uZ2l0XG5maVxuXG5pZiBbIC16IFwiJHtVU0VSTkFNRX1cIiBdICYmIFsgLXogXCIke0FDQ0VTU19UT0tFTn1cIiBdOyB0aGVuXG4gICAgZWNobyAtZSBcInVzaW5nIGFub24gYXBpIGNhbGxcIlxuZWxzZVxuICAgIEdJVF9BRERSRVNTPVwiaHR0cHM6Ly8ke1VTRVJOQU1FfToke0FDQ0VTU19UT0tFTn1AJChlY2hvIC1lICR7R0lUX0FERFJFU1N9IHwgY3V0IC1kLyAtZjMtKVwiXG5maVxuXG5pZiBbIFwiJChscyAtQSAvbW50L3NlcnZlcilcIiBdOyB0aGVuXG4gICAgaWYgWyAtZCAuZ2l0IF07IHRoZW5cbiAgICAgICAgaWYgWyAtZiAuZ2l0L2NvbmZpZyBdOyB0aGVuXG4gICAgICAgICAgICBPUklHSU49JChnaXQgY29uZmlnIC0tZ2V0IHJlbW90ZS5vcmlnaW4udXJsKVxuICAgICAgICBlbHNlXG4gICAgICAgICAgICBleGl0IDEwXG4gICAgICAgIGZpXG4gICAgZmlcbiAgICBpZiBbIFwiJHtPUklHSU59XCIgPT0gXCIke0dJVF9BRERSRVNTfVwiIF07IHRoZW4gZ2l0IHB1bGw7IGZpXG5lbHNlXG4gICAgaWYgWyAteiAke0JSQU5DSH0gXTsgdGhlblxuICAgICAgICBnaXQgY2xvbmUgJHtHSVRfQUREUkVTU30gLlxuICAgIGVsc2VcbiAgICAgICAgZ2l0IGNsb25lIC0tc2luZ2xlLWJyYW5jaCAtLWJyYW5jaCAke0JSQU5DSH0gJHtHSVRfQUREUkVTU30gLlxuICAgIGZpXG5maVxuXG5lY2hvIFwiTWVuZ2VjZWsgZGVwZW5kZW5jaWVzIG5vZGVqcy4uLlwiXG5pZiBbIC1mIC9tbnQvc2VydmVyL3BhY2thZ2UuanNvbiBdOyB0aGVuXG4gICAgaWYgWyBcIiR7UEFDS0FHRV9NQU5BR0VSfVwiID09IFwibnBtXCIgXTsgdGhlblxuICAgICAgICBlY2hvIFwiLS0+IE1lbmphbGFua2FuIGluc3RhbGFzaSBtZW5nZ3VuYWthbiBOUE0gKE1vZGU6IGxlZ2FjeS1wZWVyLWRlcHMpXCJcbiAgICAgICAgcm0gLXJmIG5vZGVfbW9kdWxlcyBwYWNrYWdlLWxvY2suanNvblxuICAgICAgICB5ZXMgXCJcIiB8IG5wbSBpbnN0YWxsIC0tcHJvZHVjdGlvbiAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXRcbiAgICBlbHNlXG4gICAgICAgIGVjaG8gXCItLT4gTWVuamFsYW5rYW4gaW5zdGFsYXNpIG1lbmdndW5ha2FuIFlBUk4gKE1vZGU6IGlnbm9yZS1lbmdpbmVzKVwiXG4gICAgICAgIHJtIC1mIHBhY2thZ2UtbG9jay5qc29uXG4gICAgICAgIHllcyB8IHlhcm4gaW5zdGFsbCAtLXByb2R1Y3Rpb24gLS1ub24taW50ZXJhY3RpdmUgLS1pZ25vcmUtZW5naW5lc1xuICAgIGZpXG5maVxuXG5yZXFfZmlsZT0ke1JFUVVJUkVNRU5UU19GSUxFOi1yZXF1aXJlbWVudHMudHh0fVxuaWYgWyAtZiAvbW50L3NlcnZlci8kcmVxX2ZpbGUgXTsgdGhlblxuICAgIGVjaG8gXCItLT4gTWVuZ2luc3RhbCBsaWJyYXJ5IFB5dGhvbiBkYXJpICRyZXFfZmlsZS4uLlwiXG4gICAgcGlwIGluc3RhbGwgLXIgJHJlcV9maWxlXG5maVxuXG5lY2hvIC1lIFwiaW5zdGFsbCBjb21wbGV0ZVwiXG5leGl0IDAiLCJjb250YWluZXIiOiJkZWJpYW46YnVsbHNleWUtc2xpbSIsImVudHJ5cG9pbnQiOiJiYXNoIn19LCJ2YXJpYWJsZXMiOlt7Im5hbWUiOiJBS1RJRktBTiBQTTIgTUFOQUdFUj8gKE1VTFRJLUJPVCkiLCJkZXNjcmlwdGlvbiI6IjEgPSBBa3RpZmthbiBQTTIgTWFuYWdlciBVSS4gQmVyZ3VuYSB1bnR1ayBtZW5qYWxhbmthbiBCQU5ZQUsgYm90IHNla2FsaWd1cyBkYWxhbSAxIHBhbmVsIChzZXRpYXAgYm90IGRpIGZvbGRlciBzZW5kaXJpKS4gMCA9IE1hdGlrYW4sIHNlcnZlciBsYW5nc3VuZyBqYWxhbmthbiBwZXJpbnRhaCBkaSBDTURfUlVOIHNhamEgKG1vZGUgYmlhc2EpLiBEZWZhdWx0OiAwIChtYXRpKS4iLCJlbnZfdmFyaWFibGUiOiJFTkFCTEVfUE0yIiwiZGVmYXVsdF92YWx1ZSI6IjAiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfGJvb2xlYW4iLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkFLVElGS0FOIFNTSCBTRVJWRVI/IiwiZGVzY3JpcHRpb24iOiIxID0gQWt0aWZrYW4gU1NIIFNlcnZlciAoYmlzYSBjb25uZWN0IHZpYSBTU0ggY2xpZW50IGtlIHBvcnQgeWFuZyBkaWFsb2thc2lrYW4gcGFuZWwpLiAwID0gTWF0aWthbi4gSmlrYSBkaWFrdGlma2FuIGRhbiBwYXNzd29yZCBiZWx1bSBhZGEsIHNpc3RlbSBha2FuIG1pbnRhIGJ1YXQgcGFzc3dvcmQgc2FhdCBmaXJzdCBzdGFydC4gRGVmYXVsdDogMCAobWF0aSkuIiwiZW52X3ZhcmlhYmxlIjoiRU5BQkxFX1NTSCIsImRlZmF1bHRfdmFsdWUiOiIwIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxib29sZWFuIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJTU0ggVVNFUk5BTUUgKExPR0lOKSIsImRlc2NyaXB0aW9uIjoiVXNlcm5hbWUgdW50dWsgbG9naW4gU1NILiBEZWZhdWx0OiByb290LiBIYW55YSBkaXBha2FpIGthbGF1IEVOQUJMRV9TU0ggPSAxLiIsImVudl92YXJpYWJsZSI6IlNTSF9VU0VSIiwiZGVmYXVsdF92YWx1ZSI6InJvb3QiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiU1NIIFBBU1NXT1JEIChPUFNJT05BTCkiLCJkZXNjcmlwdGlvbiI6IklzaSBwYXNzd29yZCBTU0ggZGkgc2luaSAobGFuZ3N1bmcgc2V0IHRhbnBhIHByb21wdCkuIEtvc29uZ2thbiA9IHNpc3RlbSBtaW50YSBwYXNzd29yZCBzYWF0IHBlcnRhbWEga2FsaSBzdGFydCAoZGlzaW1wYW4ga2UgZmlsZSAuc3NoLXBhc3N3b3JkKS4gSGFueWEgcmVsZXZhbiBqaWthIEVOQUJMRV9TU0ggPSAxLiIsImVudl92YXJpYWJsZSI6IlNTSF9QQVNTV09SRCIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiU1NIIERJU1BMQVkgVVNFUiAoUFJPTVBUKSIsImRlc2NyaXB0aW9uIjoiTmFtYSB5YW5nIG11bmN1bCBkaSBwcm9tcHQgU1NIIChjb250b2g6IHNzaEBuYW1hc2VydmVyOn4kKS4gRGVmYXVsdDogc3NoLiBEaXNwbGF5IGhvc3Qgb3RvbWF0aXMgcGFrYWkgbmFtYSBzZXJ2ZXIgZGkgcGFuZWwuIiwiZW52X3ZhcmlhYmxlIjoiU1NIX0RJU1BMQVlfVVNFUiIsImRlZmF1bHRfdmFsdWUiOiJzc2giLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiUEFDS0FHRSBNQU5BR0VSIChZQVJOIC8gTlBNKSIsImRlc2NyaXB0aW9uIjoiUGlsaWggcGFja2FnZSBtYW5hZ2VyIHVudHVrIGluc3RhbGwgbW9kdWwgTm9kZUpTLiBLZXRpayAneWFybicgYXRhdSAnbnBtJy4gUmVrb21lbmRhc2k6IHlhcm4gKGxlYmloIGphcmFuZyBlcnJvciBkaSBCYWlsZXlzIGRsbCkuIEhhbnlhIGphbGFuIGppa2EgYWRhIHBhY2thZ2UuanNvbi4iLCJlbnZfdmFyaWFibGUiOiJQQUNLQUdFX01BTkFHRVIiLCJkZWZhdWx0X3ZhbHVlIjoieWFybiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nfGluOnlhcm4sbnBtIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJQRVJJTlRBSCBKQUxBTktBTiBCT1QgKENNRF9SVU4pIiwiZGVzY3JpcHRpb24iOiJQZXJpbnRhaCB5YW5nIGRpamFsYW5rYW4gc2FhdCBFTkFCTEVfUE0yID0gMCAobW9kZSBiaWFzYSkuIENvbnRvaDogeWFybiBzdGFydCB8IG5wbSBzdGFydCB8IG5vZGUgaW5kZXguanMgfCBweXRob24zIG1haW4ucHkuIFdhamliIGRpaXNpIGthbGF1IFBNMiBkaW1hdGlrYW4uIiwiZW52X3ZhcmlhYmxlIjoiQ01EX1JVTiIsImRlZmF1bHRfdmFsdWUiOiJ5YXJuIHN0YXJ0IiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJyZXF1aXJlZHxzdHJpbmciLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkZJTEUgUkVRVUlSRU1FTlRTIFBZVEhPTiIsImRlc2NyaXB0aW9uIjoiTmFtYSBmaWxlIGRhZnRhciBsaWJyYXJ5IFB5dGhvbiAoc3RhbmRhcjogcmVxdWlyZW1lbnRzLnR4dCkuIE90b21hdGlzIGRpLWluc3RhbGwgc2FhdCBzdGFydCBqaWthIGZpbGUgZGl0ZW11a2FuLiIsImVudl92YXJpYWJsZSI6IlJFUVVJUkVNRU5UU19GSUxFIiwiZGVmYXVsdF92YWx1ZSI6InJlcXVpcmVtZW50cy50eHQiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiQVVUTyBVUERBVEUgREFSSSBHSVQ/IiwiZGVzY3JpcHRpb24iOiIxID0gU2V0aWFwIHN0YXJ0IHNlcnZlciwgb3RvbWF0aXMgZ2l0IHB1bGwgKGFtYmlsIHVwZGF0ZSB0ZXJiYXJ1IGRhcmkgcmVwbykuIDAgPSBUaWRhay4gSGFueWEgYmVybGFrdSBqaWthIGZvbGRlciBzdWRhaCBhZGEgLmdpdC4iLCJlbnZfdmFyaWFibGUiOiJBVVRPX1VQREFURSIsImRlZmF1bHRfdmFsdWUiOiIwIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxib29sZWFuIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJDTE9VREZMQVJFRCBUT0tFTiAoT1BTSU9OQUwpIiwiZGVzY3JpcHRpb24iOiJUb2tlbiBDbG91ZGZsYXJlIFR1bm5lbC4gSmlrYSBkaWlzaSwgc2VydmVyIG90b21hdGlzIGRvd25sb2FkICYgamFsYW5rYW4gY2xvdWRmbGFyZWQgZGkgYmFja2dyb3VuZCAodW50dWsgZXhwb3NlIGJvdC93ZWIgdGFucGEgcG9ydCBmb3J3YXJkKS4iLCJlbnZfdmFyaWFibGUiOiJDTE9VREZMQVJFRF9UT0tFTiIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiTU9ERSBVUExPQUQgTUFOVUFMPyIsImRlc2NyaXB0aW9uIjoiMSA9IEthbXUgdXBsb2FkIGZpbGUgYm90IHNlbmRpcmkgbGV3YXQgdGFiIEZpbGVzIChkaXNhcmFua2FuKS4gMCA9IFNhYXQgUmVpbnN0YWxsIFNlcnZlciwgb3RvbWF0aXMgY2xvbmUgZGFyaSBHSVRfQUREUkVTUy4gTW9kZSBjbG9uZSBIQU5ZQSBqYWxhbiBrYWxhdSB0ZWthbiB0b21ib2wgUmVpbnN0YWxsIFNlcnZlci4iLCJlbnZfdmFyaWFibGUiOiJVU0VSX1VQTE9BRCIsImRlZmF1bHRfdmFsdWUiOiIxIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxib29sZWFuIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJMSU5LIFJFUE9TSVRPUkkgR0lUIChPUFNJT05BTCkiLCJkZXNjcmlwdGlvbiI6IkxpbmsgR2l0SHViIHJlcG8gKGNvbnRvaDogaHR0cHM6Ly9naXRodWIuY29tL3VzZXIvcmVwbykuIEFnYXIgdGVyZG93bmxvYWQsIFdBSklCIHRla2FuIHRvbWJvbCBSZWluc3RhbGwgU2VydmVyIGRpIFNldHRpbmdzIHNldGVsYWggbWVuZ2lzaSBsaW5rIGluaS4iLCJlbnZfdmFyaWFibGUiOiJHSVRfQUREUkVTUyIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiQlJBTkNIIEdJVCIsImRlc2NyaXB0aW9uIjoiQnJhbmNoIHlhbmcgaW5naW4gZGktY2xvbmUgKGtvc29uZyA9IGRlZmF1bHQgYnJhbmNoKS4iLCJlbnZfdmFyaWFibGUiOiJCUkFOQ0giLCJkZWZhdWx0X3ZhbHVlIjoiIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxzdHJpbmciLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkdpdCBVc2VybmFtZSIsImRlc2NyaXB0aW9uIjoiVXNlcm5hbWUgR2l0ICh1bnR1ayByZXBvIHByaXZhdGUpLiIsImVudl92YXJpYWJsZSI6IlVTRVJOQU1FIiwiZGVmYXVsdF92YWx1ZSI6IiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJHaXQgQWNjZXNzIFRva2VuIiwiZGVzY3JpcHRpb24iOiJQZXJzb25hbCBBY2Nlc3MgVG9rZW4gR2l0ICh1bnR1ayByZXBvIHByaXZhdGUpLiIsImVudl92YXJpYWJsZSI6IkFDQ0VTU19UT0tFTiIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In1dfQ=="
EGG_TMP_DIR="$(mktemp -d /tmp/rafz-egg.XXXXXX)"
chmod 700 "$EGG_TMP_DIR"
printf '%s' "$EGG_B64" | base64 -d > "$EGG_TMP_DIR/egg.json"
chmod 600 "$EGG_TMP_DIR/egg.json"
# Jangan biarkan salinan world-readable di /tmp/egg.json
rm -f /tmp/egg.json /tmp/egg_import.json 2>/dev/null || true

python3 - <<PYC || { rm -rf "$EGG_TMP_DIR"; error_exit 1 "egg.json tidak valid"; }
import json
d = json.load(open("$EGG_TMP_DIR/egg.json"))
assert len(d.get("startup", "")) > 0, "EGG_STARTUP_EMPTY"
sc = d.get("scripts") or {}
ins = sc.get("installation") or {}
if not (isinstance(ins, dict) and ins.get("script")):
    d.setdefault("scripts", {})["installation"] = {
        "script": "#!/bin/bash\\necho install\\nexit 0",
        "container": "ghcr.io/parkervcp/installers:debian",
        "entrypoint": "bash",
    }
json.dump(d, open("$EGG_TMP_DIR/egg.json", "w"), ensure_ascii=False)
print(f"EGG_OK name={d.get('name')} startup={len(d['startup'])} vars={len(d.get('variables', []))}")
PYC

info "Import egg via panel (secured temp)..."
cat > "$EGG_TMP_DIR/rafz_egg.php" <<'PHP'
<?php
require "/var/www/pterodactyl/vendor/autoload.php";
$app = require_once "/var/www/pterodactyl/bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$eggPath = getenv("EGG_JSON") ?: "/tmp/egg.json";
$eggData = json_decode(file_get_contents($eggPath), true);
if (!$eggData) { echo "EGG_JSON_ERROR\n"; exit(1); }

$nestName = getenv("NEST_NAME") ?: "bot";
$nest = \Pterodactyl\Models\Nest::where("name", $nestName)->first();
if (!$nest) {
    $nest = new \Pterodactyl\Models\Nest();
    $nest->author = "rafzhost@rafzhost.my.id";
    $nest->name = $nestName;
    $nest->description = "Private bot nest — export restricted";
    $nest->save();
}
$nestId = (int) $nest->id;
echo "NEST_ID=" . $nestId . "\n";

// Hapus egg lama dengan nama sama (re-import bersih)
\Pterodactyl\Models\Egg::where("nest_id", $nestId)
    ->where("name", $eggData["name"] ?? "")
    ->delete();

$tmp = dirname($eggPath) . "/egg_import.json";
file_put_contents($tmp, json_encode($eggData, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
chmod($tmp, 0600);
$file = new \Illuminate\Http\UploadedFile($tmp, "egg.json", "application/json", null, true);
$egg = app(\Pterodactyl\Services\Eggs\Sharing\EggImporterService::class)->handle($file, $nestId);
echo "EGG_ID=" . $egg->id . "\n";
echo "IMPORT_METHOD=service\n";
PHP
chmod 600 "$EGG_TMP_DIR/rafz_egg.php"

EGG_OUTPUT="$(
  cd /var/www/pterodactyl && \
  NEST_NAME="$EGG_NEST_NAME" EGG_JSON="$EGG_TMP_DIR/egg.json" \
  php "$EGG_TMP_DIR/rafz_egg.php" 2>&1
)" || {
  rm -rf "$EGG_TMP_DIR"
  shred -u /tmp/egg.json /tmp/egg_import.json 2>/dev/null || rm -f /tmp/egg.json /tmp/egg_import.json
  error_exit 1 "Egg import gagal: $EGG_OUTPUT"
}
echo "$EGG_OUTPUT"
EGG_ID="$(printf '%s\n' "$EGG_OUTPUT" | sed -n 's/^EGG_ID=//p' | head -1)"
NEST_ID="$(printf '%s\n' "$EGG_OUTPUT" | sed -n 's/^NEST_ID=//p' | head -1)"

# === SECURITY: hapus semua jejak egg di disk ===
rm -rf "$EGG_TMP_DIR"
shred -u /tmp/egg.json /tmp/egg_import.json 2>/dev/null || rm -f /tmp/egg.json /tmp/egg_import.json
find /tmp -maxdepth 1 -name 'egg*.json' -user root -delete 2>/dev/null || true
find /tmp -maxdepth 1 -name 'rafz-egg.*' -user root -exec rm -rf {} + 2>/dev/null || true
# unset B64 dari environment shell ini
unset EGG_B64

[[ -n "$EGG_ID" && "$EGG_ID" != "0" ]] || error_exit 1 "Egg import gagal"
ok "Egg berhasil diimport (secured). ID: $EGG_ID  Nest ID: $NEST_ID"

# Best-effort: batasi EXPORT egg — hanya user id=1 (root admin) yang boleh
info "Hardening: batasi export egg di panel (non-root = 403)..."
set +e
EXPORT_CTRL="/var/www/pterodactyl/app/Http/Controllers/Admin/Nests/EggShareController.php"
if [[ -f "$EXPORT_CTRL" ]] && ! grep -q 'RAFZ_EGG_EXPORT_GUARD' "$EXPORT_CTRL" 2>/dev/null; then
  cp -a "$EXPORT_CTRL" "${EXPORT_CTRL}.bak.rafz" 2>/dev/null || true
  export EXPORT_CTRL; php -r '
    $f = getenv("EXPORT_CTRL");
    if (!$f || !is_file($f)) { echo "NO_CTRL
"; exit(0); }
    $c = file_get_contents($f);
    if (strpos($c, "RAFZ_EGG_EXPORT_GUARD") !== false) { echo "ALREADY
"; exit(0); }
    $guard = "
        // RAFZ_EGG_EXPORT_GUARD
        if (auth()->id() !== 1) {
            abort(403, "Egg export disabled by security policy");
        }
";
    $c2 = preg_replace(
        "/(function\s+export\s*\([^)]*\)\s*\{)/",
        "$1".$guard,
        $c,
        1,
        $count
    );
    if ($count > 0) {
        file_put_contents($f, $c2);
        echo "EXPORT_GUARD_OK
";
    } else {
        echo "EXPORT_GUARD_SKIP
";
    }
  ' 2>/dev/null || true
fi
cd /var/www/pterodactyl && php artisan route:clear >/dev/null 2>&1 || true
cd /var/www/pterodactyl && php artisan view:clear >/dev/null 2>&1 || true
set -e
ok "Egg secured (temp wiped, export non-root diblokir)."

info "Membersihkan cache Panel..."
cd /var/www/pterodactyl
php artisan config:clear >/dev/null 2>&1 || true
php artisan cache:clear  >/dev/null 2>&1 || true
php artisan view:clear   >/dev/null 2>&1 || true
php artisan route:clear  >/dev/null 2>&1 || true
chown -R www-data:www-data /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache 2>/dev/null || true
chmod -R ug+rwx /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache 2>/dev/null || true
systemctl restart php8.3-fpm 2>/dev/null || systemctl restart php8.2-fpm 2>/dev/null || true
systemctl reload nginx 2>/dev/null || true
ok "Cache Panel bersih."

# =========================================================================
# 16 RINGKASAN
# =========================================================================
STEP="16 Ringkasan"
cat > "$RESULT_FILE" <<DATA
=========================================================
RAFZHOST PTERODACTYL INSTALLATION
=========================================================
PANEL=https://$PANEL_DOMAIN
NODE=https://$NODE_DOMAIN
EMAIL=$ADMIN_EMAIL
USERNAME=$ADMIN_USERNAME
PASSWORD=$ADMIN_PASSWORD
FIRSTNAME=$ADMIN_FIRSTNAME
LASTNAME=$ADMIN_LASTNAME
LOCATION_ID=$LOCATION_ID
NODE_ID=$NODE_ID
NEST_ID=$NEST_ID
EGG_ID=$EGG_ID
ALLOCATION=$ALLOC_IP:$ALLOCATION_START-$ALLOCATION_END
ALLOC_ALIAS=$ALLOC_ALIAS
NODE_DAEMON_PORT=$DAEMON_PORT
NODE_MODE=native-ssl-$DAEMON_PORT
SSL_MODE=$SSL_MODE
SSL_CERT_NAME=$CERT_NAME
PLTA=$PLTA
PLTC=$PLTC
=========================================================
DATA
chmod 600 "$RESULT_FILE"

rm -f /tmp/panel-install.sh /tmp/wings-install.sh /tmp/lib.sh
rm -f /tmp/egg.json /tmp/egg_import.json /tmp/rafz_egg.php
rm -f "$WORK_DIR"/create_keys.php "$WORK_DIR"/decrypt_token.php "$WORK_DIR"/verify_wings.php "$WORK_DIR"/node-config.raw

STEP="Validasi akhir"
systemctl restart pteroq >/dev/null 2>&1 || true
systemctl restart nginx >/dev/null 2>&1 || true
echo
echo "===== SERVICE STATUS ====="
for s in nginx mariadb redis-server pteroq docker wings; do
    echo "$(printf '%-10s' "$s"): $(systemctl is-active $s || true)"
done
PANEL_CODE="$(curl -ksS --max-time 15 -o /dev/null -w '%{http_code}' "https://$PANEL_DOMAIN" || echo 000)"
echo "Panel HTTP : $PANEL_CODE"
[[ "$PANEL_CODE" == "200" || "$PANEL_CODE" == "302" ]] || warn "Panel HTTP code tidak normal: $PANEL_CODE"

# =========================================================================
# VERIFIKASI HTTPS (v3.3 + v3.4)
# =========================================================================
echo
echo "===== VERIFIKASI HTTPS ====="
echo "SSL Mode      : $SSL_MODE"
echo "Cert Name     : $CERT_NAME"
if [[ "$SSL_MODE" == "production" ]]; then
    if cert_covers_domains "${CERT_LIVE}/fullchain.pem" "$PANEL_DOMAIN" "$NODE_DOMAIN"; then
        ok "Cert covers: $PANEL_DOMAIN + $NODE_DOMAIN ✅"
    else
        warn "Cert TIDAK covers kedua domain — cek manual!"
    fi
    ISSUER="$(openssl x509 -in "${CERT_LIVE}/fullchain.pem" -noout -issuer 2>/dev/null | grep -oE 'O=[^,]+' | head -1 || true)"
    echo "Issuer        : ${ISSUER:-unknown}"
    EXPIRY="$(openssl x509 -in "${CERT_LIVE}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
    echo "Expiry        : ${EXPIRY:-unknown}"
elif [[ "$SSL_MODE" == "staging" ]]; then
    warn "Pakai STAGING cert — browser akan warning. Auto-retry via cron tiap 6 jam."
else
    crit "Pakai SELF-SIGNED — browser akan warning. Auto-retry via cron tiap 6 jam."
fi

# Cek mixed content
MIXED="$(curl -s --max-time 15 "https://$PANEL_DOMAIN" 2>/dev/null | grep -oE 'http://[^"'\'']+' | grep -v "$PANEL_DOMAIN" | head -3 || true)"
if [[ -n "$MIXED" ]]; then
    warn "Terdeteksi URL http:// di HTML:"
    echo "$MIXED"
else
    ok "Tidak ada mixed content."
fi
WS_CHECK="$(curl -s --max-time 15 "https://$PANEL_DOMAIN" 2>/dev/null | grep -oE 'ws://[^"'\'']+' | head -1 || true)"
[[ -z "$WS_CHECK" ]] && ok "WebSocket URL aman." || warn "Masih ada ws:// di HTML: $WS_CHECK"

# Cek Wings cert
echo
echo "===== VERIFIKASI WINGS CERT ====="
echo "Wings cert    : $NODE_CERT_PEM"
if [[ "$NODE_CERT_PEM" == *"/etc/letsencrypt/"* ]]; then
    if [[ "$NODE_CERT_PEM" == *"staging"* ]]; then
        warn "Wings pakai STAGING LE cert — browser warning sampai retry sukses."
    else
        ok "Wings pakai PRODUCTION LE cert ✅ (browser akan hijau)"
    fi
else
    crit "Wings pakai SELF-SIGNED cert — node akan MERAH sampai retry sukses!"
fi

# Ringkasan cronjob
echo
echo "===== CRONJOB RETRY SSL ====="
if crontab -l 2>/dev/null | grep -q "rafz-ssl-retry"; then
    ok "Cronjob aktif (tiap 6 jam) — log: $SSL_RETRY_LOG"
    echo "Manual retry : sudo /usr/local/bin/rafz-ssl-retry"
else
    warn "Cronjob retry TIDAK terpasang — jalankan manual: sudo /usr/local/bin/rafz-ssl-retry"
fi
echo

banner "INSTALLASI SELESAI"
echo
echo "========================================="
echo "  DATA LOGIN PANEL"
echo "========================================="
echo " URL      : https://$PANEL_DOMAIN"
echo " Email    : $ADMIN_EMAIL"
echo " Username : $ADMIN_USERNAME"
echo " Password : $ADMIN_PASSWORD"
echo "========================================="
echo
echo "========================================="
echo "  API KEYS"
echo "========================================="
echo " PLTA     : $PLTA"
echo " PLTC     : ${PLTC:-(gagal dibuat — buat manual di panel)}"
echo "========================================="
echo
echo "========================================="
echo "  NODE / IDS"
echo "========================================="
echo " Node URL : https://$NODE_DOMAIN:$DAEMON_PORT (TLS native)"
echo " Location : $LOCATION_ID"
echo " Node ID  : $NODE_ID"
echo " Nest ID  : $NEST_ID"
echo " Egg ID   : $EGG_ID"
echo " Alloc    : $ALLOC_IP:$ALLOCATION_START-$ALLOCATION_END ($ALLOC_ALIAS)"
echo " SFTP     : $NODE_DOMAIN:$SFTP_PORT"
echo " SSL Mode : $SSL_MODE ($CERT_NAME)"
echo "========================================="
echo
echo " File data : $RESULT_FILE"
echo " Log       : $LOG_FILE"
echo " SSL log   : $SSL_RETRY_LOG"
echo
if [[ "$SSL_MODE" != "production" ]]; then
    warn "⚠️  SSL belum production — jalankan untuk retry kapan saja:"
    warn "    sudo /usr/local/bin/rafz-ssl-retry"
    warn "    (cronjob otomatis retry tiap 6 jam)"
fi
ok "Panel + Wings + Location + Node + Allocation + Egg selesai."
echo
info "Login: https://$PANEL_DOMAIN  |  $ADMIN_USERNAME / $ADMIN_PASSWORD"