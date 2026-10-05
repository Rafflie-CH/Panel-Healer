#!/usr/bin/env bash
# =========================================================================
# RAFZHOST - GOD MODE INSTALLER (FIXED & TESTED)
# Panel + Wings + Location + Node + Allocation + Egg
# =========================================================================
# v3.5 — Perbaikan menyeluruh SSL (auto-handle rate limit + unified cert):
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
banner "[15] Import Egg — Nusantara Project GOD MODE"
info "Menulis egg.json..."
EGG_B64="eyJfY29tbWVudCI6IkRPIE5PVCBFRElUIiwibWV0YSI6eyJ2ZXJzaW9uIjoiUFRETF92MiIsInVwZGF0ZV91cmwiOm51bGx9LCJleHBvcnRlZF9hdCI6IjIwMjYtMDgtMjRUMDY6MzQ6MDYrMDc6MDAiLCJuYW1lIjoiTnVzYW50YXJhIFByb2plY3QgLSBVTFRJTUFURSBHT0QgTU9ERSAoVW5pZmllZCkiLCJhdXRob3IiOiJyYWZ6aG9zdEByYWZ6aG9zdC5teS5pZCIsImRlc2NyaXB0aW9uIjoiU2F0dSBFZ2cgdW50dWsgbWVuZ3Vhc2FpIHNlbXVhbnlhLiBCaXNhIHN3aXRjaCBhbnRhcmEgWUFSTiAvIE5QTSBsYW5nc3VuZyBkYXJpIHBhbmVsLiIsImZlYXR1cmVzIjpbXSwiZG9ja2VyX2ltYWdlcyI6eyJOb2RlSlMgMjQiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjQiLCJOb2RlSlMgMjMiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjMiLCJOb2RlSlMgMjIiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjIiLCJOb2RlSlMgMjEiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjEiLCJOb2RlSlMgMjAiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMjAiLCJOb2RlSlMgMTkiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTkiLCJOb2RlSlMgMTgiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTgiLCJOb2RlSlMgMTciOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTciLCJOb2RlSlMgMTYiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTYiLCJOb2RlSlMgMTUiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpub2RlanNfMTUiLCJQeXRob24gMy4xMiI6ImdoY3IuaW8vcGFya2VydmNwL3lvbGtzOnB5dGhvbl8zLjEyIiwiUHl0aG9uIDMuMTEiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpweXRob25fMy4xMSIsIlB5dGhvbiAzLjEwIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6cHl0aG9uXzMuMTAiLCJQeXRob24gMy45IjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6cHl0aG9uXzMuOSIsIlB5dGhvbiAzLjgiOiJnaGNyLmlvL3BhcmtlcnZjcC95b2xrczpweXRob25fMy44IiwiRGViaWFuIE9TIChVbml2ZXJzYWwpIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6ZGViaWFuIiwiVWJ1bnR1IE9TIChVbml2ZXJzYWwpIjoiZ2hjci5pby9wYXJrZXJ2Y3AveW9sa3M6dWJ1bnR1In0sImZpbGVfZGVueWxpc3QiOltdLCJzdGFydHVwIjoiaWYgW1sgLWQgLmdpdCBdXSAmJiBbWyBcInt7QVVUT19VUERBVEV9fVwiID09IFwiMVwiIF1dOyB0aGVuIGdpdCBwdWxsOyBmaTsgaWYgW1sgISAteiAke0NMT1VEUkxBUkVEX1RPS0VOfSBdXTsgdGhlbiBlY2hvIFwiTWVtdWxhaSBDbG91ZGZsYXJlZCBUdW5uZWwuLi5cIjsgd2dldCAtcSBodHRwczovL2dpdGh1Yi5jb20vY2xvdWRmbGFyZS9jbG91ZGZsYXJlZC9yZWxlYXNlcy9sYXRlc3QvZG93bmxvYWQvY2xvdWRmbGFyZWQtbGludXgtYW1kNjQgLU8gY2xvdWRmbGFyZWQgJiYgY2htb2QgK3ggY2xvdWRmbGFyZWQgJiYgLi9jbG91ZGZsYXJlZCB0dW5uZWwgLS1uby1hdXRvdXBkYXRlIHJ1biAtLXRva2VuICR7Q0xPVURGTEFSRURfVE9LRU59ID4gL2Rldi9udWxsIDI+JjEgJiBmaTsgcmVxX2ZpbGU9JHtSRVFVSVJFTUVOVFNfRklMRTotcmVxdWlyZW1lbnRzLnR4dH07IGlmIFsgLWYgL2hvbWUvY29udGFpbmVyLyRyZXFfZmlsZSBdOyB0aGVuIHBpcCBpbnN0YWxsIC1yICRyZXFfZmlsZTsgZmk7IGlmIFsgXCIke1BBQ0tBR0VfTUFOQUdFUn1cIiA9PSBcIm5wbVwiIF07IHRoZW4gaWYgW1sgISAteiAke05PREVfUEFDS0FHRVN9IF1dOyB0aGVuIHllcyBcIlwiIHwgbnBtIGluc3RhbGwgJHtOT0RFX1BBQ0tBR0VTfSAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXQ7IGZpOyBpZiBbWyAhIC16ICR7VU5OT0RFX1BBQ0tBR0VTfSBdXTsgdGhlbiB5ZXMgXCJcIiB8IG5wbSB1bmluc3RhbGwgJHtVTk5PREVfUEFDS0FHRVN9IC0tbm8tZnVuZCAtLW5vLWF1ZGl0OyBmaTsgaWYgWyAtZiAvaG9tZS9jb250YWluZXIvcGFja2FnZS5qc29uIF07IHRoZW4geWVzIFwiXCIgfCBucG0gaW5zdGFsbCAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXQ7IGZpOyBybSAtcmYgLm5wbSAubG9nIC5jYWNoZSAtLWZvcmNlOyBlbHNlIGlmIFtbICEgLXogJHtOT0RFX1BBQ0tBR0VTfSBdXTsgdGhlbiB5ZXMgfCB5YXJuIGFkZCAke05PREVfUEFDS0FHRVN9IC0tbm9uLWludGVyYWN0aXZlIC0taWdub3JlLWVuZ2luZXM7IGZpOyBpZiBbWyAhIC16ICR7VU5OT0RFX1BBQ0tBR0VTfSBdXTsgdGhlbiB5ZXMgfCB5YXJuIHJlbW92ZSAke1VOTk9ERV9QQUNLQUdFU30gLS1ub24taW50ZXJhY3RpdmU7IGZpOyBpZiBbIC1mIC9ob21lL2NvbnRhaW5lci9wYWNrYWdlLmpzb24gXTsgdGhlbiB5ZXMgfCB5YXJuIGluc3RhbGwgLS1ub24taW50ZXJhY3RpdmUgLS1pZ25vcmUtZW5naW5lczsgZmk7IHJtIC1yZiAubnBtIC5sb2cgLmNhY2hlIC55YXJuLWNhY2hlIC0tZm9yY2U7IGZpOyBpZiBbWyAhIC16ICR7Q1VTVE9NX0VOVklST05NRU5UX1ZBUklBQkxFU30gXV07IHRoZW4gdmFycz0kKGVjaG8gJHtDVVNUT01fRU5WSVJPTk1FTlRfVkFSSUFCTEVTfSB8IHRyIFwiO1wiIFwiXFxuXCIpOyBmb3IgbGluZSBpbiAkdmFyczsgZG8gZXhwb3J0ICRsaW5lOyBkb25lIGZpOyBldmFsICR7Q01EX1JVTn07IiwiY29uZmlnIjp7ImZpbGVzIjoie30iLCJzdGFydHVwIjoie1xyXG4gIFwiZG9uZVwiOiBcInJ1bm5pbmdcIlxyXG59IiwibG9ncyI6Int9Iiwic3RvcCI6Il5DIn0sInNjcmlwdHMiOnsiaW5zdGFsbGF0aW9uIjp7InNjcmlwdCI6IiMhL2Jpbi9iYXNoXG5hcHQgdXBkYXRlXG5hcHQgaW5zdGFsbCAteSBnaXQgY3VybCB3Z2V0IGpxIGZpbGUgdW56aXAgbWFrZSBnY2MgZysrIHB5dGhvbjMgcHl0aG9uMy1kZXYgcHl0aG9uMy1waXAgbGlidG9vbFxuaWYgY29tbWFuZCAtdiBucG0gJj4vZGV2L251bGw7IHRoZW4gbnBtIGluc3RhbGwgLWcgeWFybjsgZmlcbm1rZGlyIC1wIC9tbnQvc2VydmVyXG5jZCAvbW50L3NlcnZlclxuaWYgWyBcIiR7VVNFUl9VUExPQUR9XCIgPT0gXCJ0cnVlXCIgXSB8fCBbIFwiJHtVU0VSX1VQTE9BRH1cIiA9PSBcIjFcIiBdOyB0aGVuIGVjaG8gZG9uZTsgZXhpdCAwOyBmaVxuaWYgW1sgJHtHSVRfQUREUkVTU30gIT0gKi5naXQgXV07IHRoZW4gR0lUX0FERFJFU1M9JHtHSVRfQUREUkVTU30uZ2l0OyBmaVxuaWYgWyAteiBcIiR7VVNFUk5BTUV9XCIgXSAmJiBbIC16IFwiJHtBQ0NFU1NfVE9LRU59XCIgXTsgdGhlbiBlY2hvIGFub247IGVsc2UgR0lUX0FERFJFU1M9XCJodHRwczovLyR7VVNFUk5BTUV9OiR7QUNDRVNTX1RPS0VOfUAkKGVjaG8gLWUgJHtHSVRfQUREUkVTU30gfCBjdXQgLWQvIC1mMy0pXCI7IGZpXG5pZiBbIFwiJChscyAtQSAvbW50L3NlcnZlcilcIiBdOyB0aGVuIGlmIFsgLWQgLmdpdCBdICYmIFsgLWYgLmdpdC9jb25maWcgXTsgdGhlbiBPUklHSU49JChnaXQgY29uZmlnIC0tZ2V0IHJlbW90ZS5vcmlnaW4udXJsKTsgaWYgWyBcIiR7T1JJR0lOfVwiID09IFwiJHtHSVRfQUREUkVTU31cIiBdOyB0aGVuIGdpdCBwdWxsOyBmaTsgZmk7IGVsc2UgaWYgWyAteiAke0JSQU5DSH0gXTsgdGhlbiBnaXQgY2xvbmUgJHtHSVRfQUREUkVTU30gLjsgZWxzZSBnaXQgY2xvbmUgLS1zaW5nbGUtYnJhbmNoIC0tYnJhbmNoICR7QlJBTkNIfSAke0dJVF9BRERSRVNTfSAuOyBmaTsgZmlcbmlmIFsgLWYgL21udC9zZXJ2ZXIvcGFja2FnZS5qc29uIF07IHRoZW4gaWYgWyBcIiR7UEFDS0FHRV9NQU5BR0VSfVwiID09IFwibnBtXCIgXTsgdGhlbiBybSAtcmYgbm9kZV9tb2R1bGVzIHBhY2thZ2UtbG9jay5qc29uOyB5ZXMgXCJcIiB8IG5wbSBpbnN0YWxsIC0tcHJvZHVjdGlvbiAtLWxlZ2FjeS1wZWVyLWRlcHMgLS1uby1mdW5kIC0tbm8tYXVkaXQ7IGVsc2Ugcm0gLWYgcGFja2FnZS1sb2NrLmpzb247IHllcyB8IHlhcm4gaW5zdGFsbCAtLXByb2R1Y3Rpb24gLS1ub24taW50ZXJhY3RpdmUgLS1pZ25vcmUtZW5naW5lczsgZmk7IGZpXG5yZXFfZmlsZT0ke1JFUVVJUkVNRU5UU19GSUxFOi1yZXF1aXJlbWVudHMudHh0fVxuaWYgWyAtZiAvbW50L3NlcnZlci8kcmVxX2ZpbGUgXTsgdGhlbiBwaXAgaW5zdGFsbCAtciAkcmVxX2ZpbGU7IGZpXG5lY2hvIGluc3RhbGwgY29tcGxldGVcbmV4aXQgMCIsImNvbnRhaW5lciI6ImRlYmlhbjpidWxsc2V5ZS1zbGltIiwiZW50cnlwb2ludCI6ImJhc2gifX0sInZhcmlhYmxlcyI6W3sibmFtZSI6IkdVTkFLQU4gRklMRSBVUExPQUQgTUFOVUFMPyIsImRlc2NyaXB0aW9uIjoiVXBsb2FkIG1hbnVhbCAoMSkgYXRhdSBnaXQgY2xvbmUgKDApLiBSZWluc3RhbGwgU2VydmVyIHVudHVrIGFwcGx5IGdpdC4iLCJlbnZfdmFyaWFibGUiOiJVU0VSX1VQTE9EIiwiZGVmYXVsdF92YWx1ZSI6IjEiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfGJvb2xlYW4iLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IlBBQ0tBR0UgTUFOQUdFUiAoWUFSTiAvIE5QTSkiLCJkZXNjcmlwdGlvbiI6Inlhcm4gYXRhdSBucG0iLCJlbnZfdmFyaWFibGUiOiJQQUNLQUdFX01BTkFHRVIiLCJkZWZhdWx0X3ZhbHVlIjoieWFybiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nfGluOnlhcm4sbnBtIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJGSUxFIFVUQU1BIFNDUklQVCAoRU5UUlkgRklMRSkiLCJkZXNjcmlwdGlvbiI6IkNvbnRvaDogeWFybiBzdGFydCwgbnBtIHN0YXJ0LCBweXRob24gbWFpbi5weSIsImVudl92YXJpYWJsZSI6IkNNRF9SVU4iLCJkZWZhdWx0X3ZhbHVlIjoieWFybiBzdGFydCIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoicmVxdWlyZWR8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJGSUxFIExJQlJBUlkgLyBSRVFVSVJFTUVOVFMiLCJkZXNjcmlwdGlvbiI6InJlcXVpcmVtZW50cy50eHQiLCJlbnZfdmFyaWFibGUiOiJSRVFVSVJFTUVOVFNfRklMRSIsImRlZmF1bHRfdmFsdWUiOiJyZXF1aXJlbWVudHMudHh0IiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxzdHJpbmciLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkxJTksgUkVQT1NJVE9SSSBHSVQgKE9QU0lPTkFMKSIsImRlc2NyaXB0aW9uIjoiVVJMIGdpdGh1YiByZXBvLiBXYWppYiBSZWluc3RhbGwgU2VydmVyLiIsImVudl92YXJpYWJsZSI6IkdJVF9BRERSRVNTIiwiZGVmYXVsdF92YWx1ZSI6IiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJJbnN0YWxsIEJyYW5jaCIsImRlc2NyaXB0aW9uIjoiQnJhbmNoIGdpdCIsImVudl92YXJpYWJsZSI6IkJSQU5DSCIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiQXV0byBVcGRhdGUiLCJkZXNjcmlwdGlvbiI6IjE9cHVsbCBvbiBzdGFydCIsImVudl92YXJpYWJsZSI6IkFVVE9fVVBEQVRFIiwiZGVmYXVsdF92YWx1ZSI6IjEiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfGJvb2xlYW4iLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkNsb3VkZmxhcmVkIFRva2VuIiwiZGVzY3JpcHRpb24iOiJUb2tlbiBjbG91ZGZsYXJlIHR1bm5lbCIsImVudl92YXJpYWJsZSI6IkNMT1VERkxBUkVEX1RPS0VOIiwiZGVmYXVsdF92YWx1ZSI6IiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJHaXQgVXNlcm5hbWUiLCJkZXNjcmlwdGlvbiI6IkdpdCB1c2VyIiwiZW52X3ZhcmlhYmxlIjoiVVNFUk5BTUUiLCJkZWZhdWx0X3ZhbHVlIjoiIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxzdHJpbmciLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkdpdCBBY2Nlc3MgVG9rZW4iLCJkZXNjcmlwdGlvbiI6IkdpdCB0b2tlbiIsImVudl92YXJpYWJsZSI6IkFDQ0VTU19UT0tFTiIsImRlZmF1bHRfdmFsdWUiOiIiLCJ1c2VyX3ZpZXdhYmxlIjp0cnVlLCJ1c2VyX2VkaXRhYmxlIjp0cnVlLCJydWxlcyI6Im51bGxhYmxlfHN0cmluZyIsImZpZWxkX3R5cGUiOiJ0ZXh0In0seyJuYW1lIjoiRXh0cmEgTm9kZSBQYWNrYWdlcyIsImRlc2NyaXB0aW9uIjoiUGFrZXQgbnBtL3lhcm4ga2VzdHJhIChzcGFzaSkiLCJlbnZfdmFyaWFibGUiOiJOT0RFX1BBQ0tBR0VTIiwiZGVmYXVsdF92YWx1ZSI6IiIsInVzZXJfdmlld2FibGUiOnRydWUsInVzZXJfZWRpdGFibGUiOnRydWUsInJ1bGVzIjoibnVsbGFibGV8c3RyaW5nIiwiZmllbGRfdHlwZSI6InRleHQifSx7Im5hbWUiOiJVbmluc3RhbGwgTm9kZSBQYWNrYWdlcyIsImRlc2NyaXB0aW9uIjoiUGFrZXQgeWFuZyBkaS11bmluc3RhbGwiLCJlbnZfdmFyaWFibGUiOiJVTk5PREVfUEFDS0FHRVMiLCJkZWZhdWx0X3ZhbHVlIjoiIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxzdHJpbmciLCJmaWVsZF90eXBlIjoidGV4dCJ9LHsibmFtZSI6IkN1c3RvbSBFbnYgVmFyaWFibGVzIiwiZGVzY3JpcHRpb24iOiJLRVk9dmFsO0tFWTI9dmFsMiIsImVudl92YXJpYWJsZSI6IkNVU1RPTV9FTlZJUk9OTUVOVF9WQVJJQUJMRVMiLCJkZWZhdWx0X3ZhbHVlIjoiIiwidXNlcl92aWV3YWJsZSI6dHJ1ZSwidXNlcl9lZGl0YWJsZSI6dHJ1ZSwicnVsZXMiOiJudWxsYWJsZXxzdHJpbmciLCJmaWVsZF90eXBlIjoidGV4dCJ9XX0="
printf '%s' "$EGG_B64" | base64 -d > /tmp/egg.json
python3 - <<'PYC' || error_exit 1 "egg.json tidak valid"
import json
d = json.load(open('/tmp/egg.json'))
assert len(d.get('startup', '')) > 0, 'EGG_STARTUP_EMPTY'
sc = d.get('scripts') or {}
ins = sc.get('installation') or {}
if not (isinstance(ins, dict) and 'script' in ins):
    d['scripts'] = {'installation': {'script': sc.get('script', ''), 'entrypoint': sc.get('entrypoint', 'bash'), 'container': sc.get('container', 'debian:bullseye-slim')}}
    json.dump(d, open('/tmp/egg.json', 'w'), ensure_ascii=False)
print(f"EGG_OK startup={len(d['startup'])} vars={len(d.get('variables', []))}")
PYC

info "Import egg via panel..."
cat > /tmp/rafz_egg.php <<'PHP'
<?php
require "/var/www/pterodactyl/vendor/autoload.php";
$app = require_once "/var/www/pterodactyl/bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$eggData = json_decode(file_get_contents("/tmp/egg.json"), true);
if (!$eggData) { echo "EGG_JSON_ERROR\n"; exit(1); }
$nestName = getenv('NEST_NAME') ?: 'bot';
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
\Pterodactyl\Models\Egg::where("nest_id", $nestId)->where("name", $eggData["name"] ?? "")->delete();
$tmp = "/tmp/egg_import.json";
file_put_contents($tmp, json_encode($eggData, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
$file = new \Illuminate\Http\UploadedFile($tmp, "egg.json", "application/json", null, true);
$egg = app(\Pterodactyl\Services\Eggs\Sharing\EggImporterService::class)->handle($file, $nestId);
echo "EGG_ID=" . $egg->id . "\n";
echo "IMPORT_METHOD=service\n";
PHP
EGG_OUTPUT="$(cd /var/www/pterodactyl && NEST_NAME="$EGG_NEST_NAME" php /tmp/rafz_egg.php 2>&1)" || error_exit 1 "Egg import gagal: $EGG_OUTPUT"
echo "$EGG_OUTPUT"
EGG_ID="$(printf '%s\n' "$EGG_OUTPUT" | sed -n 's/^EGG_ID=//p' | head -1)"
NEST_ID="$(printf '%s\n' "$EGG_OUTPUT" | sed -n 's/^NEST_ID=//p' | head -1)"
[[ -n "$EGG_ID" && "$EGG_ID" != "0" ]] || error_exit 1 "Egg import gagal"
ok "Egg berhasil diimport. ID: $EGG_ID  Nest ID: $NEST_ID"

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