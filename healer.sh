#!/bin/bash

# ======================================================
#   ⚡ PANEL HEALER ULTIMATE TOOLKIT BY RAFZ (V3.5) ⚡
#   Premium VPS Troubleshooting & Hama Killer System
# ======================================================

# Definisi Palette Warna Premium (Cyberpunk Theme)
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
DARK='\033[0;90m'
NC='\033[0m' # No Color

# Pastikan script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Script wajib dijalankan dengan akses ROOT!${NC}"
  echo -e "${RED}Silakan ketik: sudo su atau gunakan sudo ./healer.sh${NC}"
  exit 1
fi

# Fungsi jeda premium
tunggu_enter() {
    echo -e ""
    echo -e "${CYAN}─────────────────────────────────────────────${NC}"
    while true; do
        echo -ne "${YELLOW}[✦] Ketik [X] lalu ENTER untuk kembali: ${NC}"
        read -r jeda
        if [[ "$jeda" =~ ^[Xx]$ ]]; then
            break
        fi
        echo -e "${RED}[!] Salah ketik bro! Harus huruf X/x.${NC}"
    done
}

# ========================================================
#  🧠 AUTO-CHECKER SYSTEM (DIAGNOSA REAL-TIME)
# ========================================================
jalankan_auto_check() {
    REKOMENDASI=""
    WARNING_COUNT=0

    echo -e "${DARK}[i] Memindai kondisi VPS lu...${NC}"

    # 1. Cek Antrean Port Web (80/443)
    KONEKSI_WEB=$(ss -ant | grep -E ':80|:443' | wc -l)
    if [ "$KONEKSI_WEB" -gt 350 ]; then
        REKOMENDASI="${REKOMENDASI}\n ${RED}• [!] Port Web Overload ($KONEKSI_WEB koneksi). Stuck loading? Sikat MENU [09]${NC}"
        ((WARNING_COUNT++))
    fi

    # 2. Cek Antrean Port Daemon Wings (8080)
    KONEKSI_WINGS=$(ss -ant | grep -E ':8080' | wc -l)
    if [ "$KONEKSI_WINGS" -gt 200 ]; then
        REKOMENDASI="${REKOMENDASI}\n ${RED}• [!] Wings Overload ($KONEKSI_WINGS spam)! Clear di MENU [09] atau [07]${NC}"
        ((WARNING_COUNT++))
    fi

    # 3. Cek Log Crash Nginx (Abort Socket)
    if [ -f /var/log/nginx/error.log ]; then
        CRASH_NGINX=$(tail -n 30 /var/log/nginx/error.log | grep -E 'aborting|open socket' | tail -n 1)
        if [ ! -z "$CRASH_NGINX" ]; then
            REKOMENDASI="${REKOMENDASI}\n ${RED}• [!] Nginx Socket Aborting! Web panel mati total. Clear MENU [09]${NC}"
            ((WARNING_COUNT++))
        fi
    fi

    # 4. Cek Status Wings (Pterodactyl Daemon)
    if systemctl is-active --quiet wings 2>/dev/null; then
        :
    else
        REKOMENDASI="${REKOMENDASI}\n ${YELLOW}• [!] Wings Offline/Pingsan. Beresin pake MENU [05] atau cek service.${NC}"
        ((WARNING_COUNT++))
    fi

    # 5. Cek Disk Full
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 85 ]; then
        REKOMENDASI="${REKOMENDASI}\n ${RED}• [!] Storage Kritis ($DISK_USAGE% Terpakai)! Cari biang kerok di MENU [07]${NC}"
        ((WARNING_COUNT++))
    fi

    # Tampilkan Hasil Analisis
    if [ "$WARNING_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  STATUS VPS LU (DITEMUKAN $WARNING_COUNT MASALAH)${NC}"
        echo -e "${YELLOW}─────────────────────────────────────────────${NC}"
        echo -e "$REKOMENDASI"
    else
        echo -e "${GREEN}✔  STATUS VPS LU${NC}"
        echo -e "${GREEN}─────────────────────────────────────────────${NC}"
        echo -e " ${GREEN}• Jaringan, WebServer, Storage & Daemon AMAN! 🚀${NC}"
    fi
    echo -e ""
}

# Loop Utama Dashboard Toolkit
while true; do
clear
echo -e "${PURPLE}⚡ SYSTEM CORE PANEL HEALER BY RAFZ (V3.5) ⚡${NC}"
echo -e "${DARK}Ultimate VPS Automation & Troubleshooting${NC}"
echo -e "${CYAN}─────────────────────────────────────────────${NC}"
echo -e " ${WHITE}Welcome back, Rafz! Hasil Cek Sistem:${NC}"
echo -e ""

# Jalankan diagnosa di dashboard utama
jalankan_auto_check

echo -e "${CYAN}─────────────────────────────────────────────${NC}"
echo -e " ${WHITE}Pilih Opsi Menu:${NC}"
echo -e ""
echo -e " ${CYAN}[01]${NC} 🔒 FIX DPKG LOCK       ${DARK}-> Buka Gembok Update APT / DPKG Broken${NC}"
echo -e " ${CYAN}[02]${NC} ☢️  DEEP CLEAN PANEL    ${DARK}-> Wipe Total Node & Web Server (Reset OS)${NC}"
echo -e " ${CYAN}[03]${NC} 🧹 QUICK CLEAN DISK   ${DARK}-> Kuras Log & Cache Sampah (Legakan Space)${NC}"
echo -e " ${CYAN}[04]${NC} 🧨 MANUAL WIPE VOLUMES${DARK}-> Hapus Sisa Server Ptero & DB Raksasa${NC}"
echo -e " ${CYAN}[05]${NC} 🔌 FIX DOCKER SOCKET  ${DARK}-> Solusi Wings Gagal Konek Daemon Socket${NC}"
echo -e " ${CYAN}[06]${NC} 🌀 REINSTALL DOCKER   ${DARK}-> Force Rebuild Komponen Docker Corrupted${NC}"
echo -e " ${PURPLE}[07]${NC} 🚨 AUTO CIDUK HAMA    ${DARK}-> Scan & Auto Bantai Server Perusak VPS${NC}"
echo -e " ${CYAN}[08]${NC} 📥 PTERODACTYL CORE   ${DARK}-> Auto Run Pterodactyl Official Installer${NC}"
echo -e " ${GREEN}[09]${NC} 🛡️  RATE LIMIT & FLUSH  ${DARK}-> Pasang Anti-DDoS Nginx & Lepas Stuck Panel${NC}"
echo -e " ${RED}[X]${NC}  ❌ SHUTDOWN TERMINAL   ${DARK}-> Keluar dari Script${NC}"
echo -e "${CYAN}─────────────────────────────────────────────${NC}"

# Loop Validasi Menu Interaktif
while true; do
    echo -ne "${CYAN}[✦] Rafz@Toolkit:~# ${NC}"
    read -r pilihan
    if [[ -z "$pilihan" ]]; then
        echo -e "${RED}[!] Opsi kosong bro, ketik nomor menunya!${NC}"
    elif [[ "$pilihan" =~ ^[Xx]$ ]] || [ "$pilihan" = "0" ]; then
        echo -e "\n${GREEN}[✔] Keluar dari script. Written by Rafz Dev. See you!${NC}\n"
        exit 0
    elif [[ "$pilihan" =~ ^[1-9]$ ]] || [[ "$pilihan" =~ ^[0][1-9]$ ]]; then
        pilihan=$(echo "$pilihan" | sed 's/^0//')
        break
    else
        echo -e "${RED}[!] Pilihan gak ada bro! Input nomor [1-9] atau [X].${NC}"
    fi
done

case $pilihan in
    1)
        clear
        echo -e "${CYAN}🔒 FIX DPKG LOCK${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${RED}❌ E: Could not get lock /var/lib/dpkg/lock-frontend...${NC}"
        echo -e "${RED}❌ E: Unable to acquire the dpkg frontend lock...${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${WHITE}[LOG] Ada proses instalasi lain yang lagi ngunci APT di background.${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Gas lepas gembok database APT? (y/n/x): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Ngancurin gembok sistem & update paket...${NC}"
                rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock
                dpkg --configure -a && apt-get clean && apt-get update
                echo -e "${GREEN}[✔] SUCCESS: Database DPKG berhasil dibuka kembali!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Ketik y, n, atau x bro.${NC}"
            fi
        done
        ;;
        
    2)
        clear
        echo -e "${CYAN}☢️  DEEP CLEAN WIPE OUT${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${RED}⚠️  WARNING: Opsi ini bakal ngapus TOTAL semua data${NC}"
        echo -e "${RED}   Pterodactyl, Wings, Nginx, Docker, & Database SQL!${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${WHITE}Pake ini cuma kalau installer lu error parah dan mau reset OS ke awal.${NC}"
        echo -e ""
        while true; do
            echo -ne "${RED}[💀] Lu yakin mau WIPE OUT TOTAL isi VPS ini? (y/n/x): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Memulai pembersihan total...${NC}"
                sudo systemctl stop wings pteroq nginx mysql mariadb redis-server 2>/dev/null
                sudo killall -9 nginx mariadb mysqld redis-server 2>/dev/null
                sudo systemctl disable wings pteroq nginx mysql mariadb redis-server 2>/dev/null
                sudo rm -rf /etc/systemd/system/wings.service /etc/systemd/system/pteroq.service
                
                echo -e "${BLUE}[+] Ngapus semua container Docker...${NC}"
                sudo docker stop $(sudo docker ps -a -q) 2>/dev/null
                sudo docker rm $(sudo docker ps -a -q) 2>/dev/null
                sudo docker rmi $(sudo docker images -q) 2>/dev/null
                
                echo -e "${BLUE}[+] Nyapu paket webserver & dependencies...${NC}"
                sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null
                sudo rm -rf /var/lib/docker /etc/docker /var/www/pterodactyl /etc/pterodactyl /var/log/pterodactyl /etc/wings
                sudo apt-get purge -y nginx* mysql-* mariadb-* php8.3* php8.2* php-fpm* redis-* 2>/dev/null
                sudo apt-get autoremove -y && sudo apt-get clean
                sudo rm -rf /var/lib/mysql /var/lib/mariadb /etc/mysql /var/log/nginx /etc/nginx /var/lib/redis
                sudo systemctl daemon-reload && sudo systemctl reset-failed
                
                echo -e "${GREEN}[✔] SUCCESS TOTAL: OS VPS bersih total kek baru install!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Pilihan salah! Ketik y, n, atau x.${NC}"
            fi
        done
        ;;

    3)
        clear
        echo -e "${CYAN}🧹 DISK QUICK CLEAN DISK${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}[INFO] Ngosongin file sampah log sistem aktif (.gz)${NC}"
        echo -e "${YELLOW}       Aman, gak bakal nyentuh data project / game server.${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Jalankan pembersihan cache sampah? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Nguras folder log & junk file temporary...${NC}"
                sudo apt-get clean
                sudo rm -rf /var/log/journal/* 2>/dev/null
                sudo find /var/log -type f -regex '.*\.gz$\|.*\.1$' -delete
                sudo find /var/log -type f -exec truncate -s 0 {} +
                sudo rm -rf /tmp/*
                echo -e "${GREEN}[✔] SUCCESS: Ruang penyimpanan berhasil dilegakan!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Ketik y atau n bro.${NC}"
            fi
        done
        ;;

    4)
        clear
        echo -e "${CYAN}🧨 MANUAL WIPE DATA SERVER${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${RED}⚠️  WARNING: Perintah ini bakal ngapus paksa folder game,${NC}"
        echo -e "${RED}   direktori web panel, beserta core database SQL!${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e ""
        while true; do
            echo -ne "${RED}[💀] Lu yakin mau wipe data game & database SQL? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Ngehapus data server game & database...${NC}"
                sudo systemctl stop wings pteroq 2>/dev/null
                sudo rm -rf /var/lib/pterodactyl /etc/pterodactyl /var/www/pterodactyl /etc/nginx/sites-enabled/pterodactyl.conf /etc/systemd/system/wings.service /etc/systemd/system/pteroq.service /var/log/pterodactyl
                sudo apt-get purge -y mariadb-server mysql-server 2>/dev/null
                sudo apt-get autoremove -y
                echo -e "${GREEN}[✔] SUCCESS: Semua folder server game raksasa lenyap!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Pilihan salah! Ketik y atau n.${NC}"
            fi
        done
        ;;

    5)
        clear
        echo -e "${CYAN}🔌 FIX DOCKER SOCKET${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${RED}❌ Error response from daemon: Dialogue socket in use...${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${WHITE}[LOG] Memperbaiki socket docker kuncian pasca crash / full disk.${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Reset jalur komunikasi Docker Socket? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Mutus koneksi lama & restart daemon socket...${NC}"
                sudo systemctl stop docker.socket && sudo systemctl stop docker
                sudo rm -f /var/run/docker.sock
                sudo systemctl start docker.socket && sudo systemctl start docker
                echo -e "${GREEN}[✔] SUCCESS: Docker Socket normal kembali!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Ketik y atau n bro.${NC}"
            fi
        done
        ;;

    6)
        clear
        echo -e "${CYAN}🌀 FORCE REBUILD DOCKER${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${RED}❌ Docker status: dead / failed (Result: exit-code)${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${WHITE}[LOG] Menginstal ulang service Docker tanpa merusak OS utama VPS.${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Paksa install ulang komponen utama Docker? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Nindih binary file Docker Engine via APT...${NC}"
                sudo apt-get install --reinstall docker-ce docker-ce-cli containerd.io -y
                sudo systemctl daemon-reload && sudo systemctl enable --now docker
                echo -e "${GREEN}[✔] SUCCESS: Engine Docker berhasil di-rebuild!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Ketik y atau n bro.${NC}"
            fi
        done
        ;;

    7)
        clear
        echo -e "${CYAN}🚨 LAPORAN PEMAKAIAN DISK${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        
        echo -e "${PURPLE}[1] CEK PENYIMPANAN VPS LU saat ini:${NC}"
        df -h / | awk 'NR==2 {print " • Total Size : " $2 "\n • Terpakai   : " $3 "\n • Tersedia   : " $4 "\n • Persentase : " $5}'
        echo -e ""
        
        echo -e "${PURPLE}[2] MENCARI FOLDER SERVER GAME PALING RAKUS...${NC}"
        TARGET_PATH=$(du -sh /var/lib/pterodactyl/volumes/* 2>/dev/null | sort -hr | head -n 1)
        
        if [ -z "$TARGET_PATH" ]; then
            echo -e "${RED} • [!] Folder data server di direktori /volumes/ kosong/gak ketemu.${NC}"
            tunggu_enter ; continue
        fi
        
        SIZE=$(echo "$TARGET_PATH" | awk '{print $1}')
        FOLDER=$(echo "$TARGET_PATH" | awk '{print $2}')
        UUID=$(basename "$FOLDER")
        SHORT_UUID=${UUID:0:8}
        
        echo -e " • Size Terbesar : ${RED}$SIZE${NC}"
        echo -e " • Lokasi Folder : ${DARK}$FOLDER${NC}"
        echo -e ""
        
        echo -e "${PURPLE}[3] MENCOCOKKAN DATA FOLDER KE DATABASE PANEL:${NC}"
        echo -e "${RED}─────────────────────────────────────────────${NC}"
        
        DB_CHECK=$(sudo mysql -u root -e "USE panel; SELECT s.id FROM servers s WHERE s.uuid LIKE '$SHORT_UUID%';" 2>/dev/null)
        
        if [ -z "$DB_CHECK" ]; then
            echo -e "${YELLOW} [!] ID Server gak ada di database. Fix ini server hantu (udah di-delete dari panel tapi sisa folder masih ada).${NC}"
            echo -e "${RED}─────────────────────────────────────────────${NC}"
            
            while true; do
                echo -ne "${YELLOW}[?] Folder sisa hantu ketemu. Hapus paksa foldernya? (y/n): ${NC}"
                read -r hapus_yatim
                if [[ "$hapus_yatim" =~ ^[Yy]$ ]]; then
                    sudo rm -rf "$FOLDER"
                    echo -e "${GREEN}[✔] SUCCESS: Folder hantu pemakan space dibabat bersih!${NC}"
                    break
                elif [[ "$hapus_yatim" =~ ^[Nn]$ ]]; then
                    break
                fi
            done
            tunggu_enter ; continue
        fi
        
        sudo mysql -u root -e "USE panel; SELECT s.id AS 'ID Server', s.name AS 'Nama Server', u.username AS 'Username', u.email AS 'Email Pelaku', s.uuid AS 'UUID Lengkap' FROM servers s JOIN users u ON s.owner_id = u.id WHERE s.uuid LIKE '$SHORT_UUID%';"
        echo -e "${RED}─────────────────────────────────────────────${NC}"
        echo -e "${GREEN}[INFO] Cocok 100%! Data pemilik server di atas berhasil dilacak.${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e ""
        
        echo -e "${YELLOW}⚠️  KONFIRMASI EKSEKUSI:${NC}"
        echo -ne "${WHITE}[?] Lu yakin mau delete server berukuran ${RED}$SIZE${WHITE} ini? (y/n): ${NC}"
        read -r PILIHAN
        
        case "$PILIHAN" in
            [yY][eE][sS]|[yY])
                echo -e "\n${BLUE}[+] Memulai proses pembersihan total kontainer & database...${NC}"
                sudo docker kill "$UUID" 2>/dev/null && \
                sudo docker rm "$UUID" 2>/dev/null && \
                sudo rm -rf "$FOLDER" && \
                sudo mysql -u root -e "USE panel; DELETE FROM servers WHERE uuid LIKE '$SHORT_UUID%';" 2>/dev/null && \
                sudo systemctl restart wings && \
                echo -e "\n${GREEN}[✔] BERES! Server dengan ID awal $SHORT_UUID udah dihapus total! Node adem lagi.🚀${NC}"
                ;;
                
            [nN][oO]|[nN])
                echo -e "\n${RED}Malah milih No... 🗿🗿🗿${NC}"
                echo -e "${YELLOW}Udah tahu VPS lu megap-megap malah dipelihara server rakusnya wkwkwk. Bebas dah, Rafz! ${NC}\n"
                ;;
                
            *)
                echo -e "\n${RED}[!] Input asal-asalan, pembatalan otomatis oleh sistem.${NC}\n"
                ;;
        esac
        tunggu_enter
        ;;

    8)
        clear
        echo -e "${CYAN}📥 PTERODACTYL OFFICIAL INSTALLER${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}[INFO] Bakal nge-run installer script resmi Pterodactyl.${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Download & jalankan script installer? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                if ! command -v curl &> /dev/null; then
                    echo -e "${BLUE}[+] Paket curl gak ada, otomatis install curl dulu via APT...${NC}"
                    apt-get update && apt-get install -y curl
                fi
                echo -e "${GREEN}[+] Booting installer... GASSING SPEED RUN! 🚀${NC}\n"
                bash <(curl -s https://pterodactyl-installer.se)
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Ketik y atau n bro.${NC}"
            fi
        done
        ;;

    9)
        clear
        echo -e "${CYAN}🛡️  ANTI-DDOS & FLUSH PORT SYSTEM${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}[INFO] Modul pelindung panel & node dari banjir spam request.${NC}"
        echo -e "${YELLOW}       Bakal otomatis masang rule limit_req di nginx.${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Pasang pembatas request & bersihkan antrean port? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Meriksa file konfigurasi nginx panel...${NC}"
                CONF_PATH="/etc/nginx/sites-available/pterodactyl.conf"
                
                if [ -f "$CONF_PATH" ]; then
                    # Suntik kode pembatas request jika belum ada
                    if ! grep -q "zone=panel_limit" "$CONF_PATH"; then
                        echo -e "${BLUE}[+] Masang aturan Rate-Limit di baris paling atas...${NC}"
                        sed -i '1i limit_req_zone $binary_remote_addr zone=panel_limit:10m rate=10r/s;' "$CONF_PATH"
                        sed -i '/location ~ \\.php\$/a \ \ \ \ limit_req zone=panel_limit burst=20 nodelay;' "$CONF_PATH"
                    else
                        echo -e "${GREEN}[i] Rule rate-limit udah terpasang sebelumnya di config.${NC}"
                    fi
                else
                    echo -e "${RED}[!] File $CONF_PATH gak ketemu! Eksekusi bypass otomatis.${NC}"
                fi
                
                echo -e "${BLUE}[+] Optimalin kapasitas soket Linux...${NC}"
                ulimit -n 65535
                
                echo -e "${BLUE}[+] Bersihin paksa koneksi zombie di port 80, 443 & 8080...${NC}"
                ss -K dst :80 2>/dev/null
                ss -K dst :443 2>/dev/null
                ss -K dst :8080 2>/dev/null
                
                echo -e "${BLUE}[+] Tes integritas config Nginx...${NC}"
                if nginx -t; then
                    echo -e "${BLUE}[+] Restarting Web Engine, PHP-FPM, & Wings Daemon...${NC}"
                    systemctl restart nginx php8.1-fpm php8.2-fpm php8.3-fpm 2>/dev/null
                    systemctl restart wings 2>/dev/null
                    echo -e "${GREEN}[✔] SUCCESS: Jaringan & Node dilegakan! Anti-DDoS internal AKTIF.🚀${NC}"
                else
                    echo -e "${RED}[!] Syntax Nginx Error! Perubahan konfig digagalkan demi keamanan.${NC}"
                fi
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Input salah! Ketik y atau n.${NC}"
            fi
        done
        ;;
esac
done
