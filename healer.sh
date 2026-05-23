#!/bin/bash

# ======================================================
#   ⚡ PANEL HEALER ULTIMATE TOOLKIT BY RAFZ (V2) ⚡
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
  echo -e "${RED}┌────────────────────────────────────────────────────────┐${NC}"
  echo -e "${RED}│ [ERROR] Script wajib dijalankan menggunakan akses ROOT! │${NC}"
  echo -e "${RED}│ Silakan ketik: sudo su atau gunakan sudo ./healer.sh   │${NC}"
  echo -e "${RED}└────────────────────────────────────────────────────────┘${NC}"
  exit 1
fi

# Fungsi jeda premium
tunggu_enter() {
    echo -e ""
    echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
    while true; do
        echo -ne "${YELLOW}[✦] Ketik [X] lalu ENTER untuk kembali ke Dashboard: ${NC}"
        read -r jeda
        if [[ "$jeda" =~ ^[Xx]$ ]]; then
            break
        fi
        echo -e "${RED}[!] Input salah bro! Harus ketik huruf X atau x.${NC}"
    done
}

# Loop Utama Dashboard Toolkit
while true; do
clear
echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${PURPLE}    ⚡ SYSTEM EXECUTIVE PANEL HEALER BY RAFZ ⚡      ${CYAN}│${NC}"
echo -e "${CYAN}│${DARK}       Ultimate VPS Automation & Troubleshooting      ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
echo -e " ${WHITE}Welcome back, Rafz! Select elite core configuration:${NC}"
echo -e ""
echo -e " ${CYAN}[01]${NC} 🔒 FIX DPKG LOCK         ${DARK}-> Fix Gembok Update APT / DPKG Broken${NC}"
echo -e " ${CYAN}[02]${NC} ☢️  DEEP CLEAN PANEL      ${DARK}-> Wipe Total Node & Web Server (Reset OS)${NC}"
echo -e " ${CYAN}[03]${NC} 🧹 QUICK CLEAN DISK     ${DARK}-> Kuras Log & Cache Sampah (Beri Sisa Space)${NC}"
echo -e " ${CYAN}[04]${NC} 🧨 MANUAL WIPE VOLUMES  ${DARK}-> Hapus Sisa Server Ptero & DB Raksasa${NC}"
echo -e " ${CYAN}[05]${NC} 🔌 FIX DOCKER SOCKET    ${DARK}-> Solusi Wings Gagal Konek Daemon Socket${NC}"
echo -e " ${CYAN}[06]${NC} 🌀 REINSTALL DOCKER     ${DARK}-> Force Rebuild Komponen Docker Corrupted${NC}"
echo -e " ${PURPLE}[07]${NC} 🚨 AUTO CIDUK HAMA KILL ${DARK}-> [NEW] Scan & Auto Bantai Server Perusak VPS${NC}"
echo -e " ${CYAN}[08]${NC} 📥 PTERODACTYL CORE     ${DARK}-> Auto Run Pterodactyl Official Installer${NC}"
echo -e " ${RED}[X]${NC}  ❌ SHUTDOWN TERMINAL     ${DARK}-> Keluar dari Framework Toolkit${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"

# Loop Validasi Menu Interaktif
while true; do
    echo -ne "${CYAN}[✦] Rafz@Toolkit:~# ${NC}"
    read -r pilihan
    if [[ -z "$pilihan" ]]; then
        echo -e "${RED}[!] Command line kosong, panggil nomor opsi menu bro!${NC}"
    elif [[ "$pilihan" =~ ^[Xx]$ ]] || [ "$pilihan" = "0" ]; then
        echo -e "\n${GREEN}[✔] Framework Closed. Script written by Rafz Dev. See you!${NC}\n"
        exit 0
    elif [[ "$pilihan" =~ ^[1-8]$ ]] || [[ "$pilihan" =~ ^[0][1-8]$ ]]; then
        # Hapus angka 0 di depan jika user mengetik 01, 02, dll
        pilihan=$(echo "$pilihan" | sed 's/^0//')
        break
    else
        echo -e "${RED}[!] Kernel Error! Code opsi [1-8 atau X] tidak terdaftar.${NC}"
    fi
done

case $pilihan in
    1)
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│               🔒 SECURITY CORE: FIX DPKG             │${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
        echo -e "${RED}❌ E: Could not get lock /var/lib/dpkg/lock-frontend...${NC}"
        echo -e "${RED}❌ E: Unable to acquire the dpkg frontend lock...${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}[LOG] Sistem mendeteksi kuncian instalasi di background.${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Eksekusi pelepasan gembok database APT? (y/n/x): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Menghancurkan gembok sistem & rekonfigurasi kernel...${NC}"
                rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock
                dpkg --configure -a && apt-get clean && apt-get update
                echo -e "${GREEN}[✔] SUCCESS: Database DPKG berhasil disucikan!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Invalid Choice! Ketik y, n, atau x.${NC}"
            fi
        done
        ;;
        
    2)
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│            ☢️  SYSTEM WIPE: DEEP CLEAN PANEL         │${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
        echo -e "${RED}⚠️  WARNING: Opsi ini menghapus TOTAL seluruh ekosistem${NC}"
        echo -e "${RED}   Pterodactyl, Wings, Nginx, Docker, & MySQL Database!${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}Gunakan jika installer gagal dan lu mau reset OS jadi baru.${NC}"
        echo -e ""
        while true; do
            echo -ne "${RED}[💀] Lu yakin mau WIPE OUT TOTAL isi VPS ini? (y/n/x): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Memulai pembersihan brutal secara bertahap...${NC}"
                sudo systemctl stop wings pteroq nginx mysql mariadb redis-server 2>/dev/null
                sudo killall -9 nginx mariadb mysqld redis-server 2>/dev/null
                sudo systemctl disable wings pteroq nginx mysql mariadb redis-server 2>/dev/null
                sudo rm -rf /etc/systemd/system/wings.service /etc/systemd/system/pteroq.service
                
                echo -e "${BLUE}[+] Menghapus sisa-sisa kontainer Docker...${NC}"
                sudo docker stop $(sudo docker ps -a -q) 2>/dev/null
                sudo docker rm $(sudo docker ps -a -q) 2>/dev/null
                sudo docker rmi $(sudo docker images -q) 2>/dev/null
                
                echo -e "${BLUE}[+] Membabat paket binary webserver & dependencies...${NC}"
                sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null
                sudo rm -rf /var/lib/docker /etc/docker /var/www/pterodactyl /etc/pterodactyl /var/log/pterodactyl /etc/wings
                sudo apt-get purge -y nginx* mysql-* mariadb-* php8.3* php8.2* php-fpm* redis-* 2>/dev/null
                sudo apt-get autoremove -y && sudo apt-get clean
                sudo rm -rf /var/lib/mysql /var/lib/mariadb /etc/mysql /var/log/nginx /etc/nginx /var/lib/redis
                sudo systemctl daemon-reload && sudo systemctl reset-failed
                
                echo -e "${GREEN}[✔] SUCCESS TOTAL: OS VPS kembali perawan & suci!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Invalid Choice! Ketik y, n, atau x.${NC}"
            fi
        done
        ;;

    3)
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│             🧹 DISK OPTIMIZER: QUICK CLEAN           │${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
        echo -e "${YELLOW}[INFO] Mengosongkan file sampah log sistem aktif (.gz)${NC}"
        echo -e "${YELLOW}       tanpa menyentuh data project atau server game.${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Jalankan pembersihan sampah cache? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Menguras tangki log & folder temporary...${NC}"
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
                echo -e "${RED}[!] Invalid Choice! Ketik y atau n.${NC}"
            fi
        done
        ;;

    4)
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│          🧨 STORAGE PURGE: MANUAL WIPE DATA          │${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
        echo -e "${RED}⚠️  WARNING: Perintah ini menghapus paksa volume game,${NC}"
        echo -e "${RED}   direktori web panel, beserta core database SQL!${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
        echo -e ""
        while true; do
            echo -ne "${RED}[💀] Lu yakin mau wipe data game & SQL server? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Melakukan pembersihan storage secara paksa...${NC}"
                sudo systemctl stop wings pteroq 2>/dev/null
                sudo rm -rf /var/lib/pterodactyl /etc/pterodactyl /var/www/pterodactyl /etc/nginx/sites-enabled/pterodactyl.conf /etc/systemd/system/wings.service /etc/systemd/system/pteroq.service /var/log/pterodactyl
                sudo apt-get purge -y mariadb-server mysql-server 2>/dev/null
                sudo apt-get autoremove -y
                echo -e "${GREEN}[✔] SUCCESS: Sisa folder data game raksasa lenyap!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Invalid Choice! Ketik y atau n.${NC}"
            fi
        done
        ;;

    5)
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│             🔌 DAEMON FIX: DOCKER SOCKET             │${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
        echo -e "${RED}❌ Error response from daemon: Dialogue socket in use...${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}[LOG] Memperbaiki kuncian socket docker pasca crash / full disk.${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Reset interface komunikasi Docker Socket? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Memutus jalur komunikasi & merestart daemon...${NC}"
                sudo systemctl stop docker.socket && sudo systemctl stop docker
                sudo rm -f /var/run/docker.sock
                sudo systemctl start docker.socket && sudo systemctl start docker
                echo -e "${GREEN}[✔] SUCCESS: Docker Socket kembali online!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Invalid Choice! Ketik y atau n.${NC}"
            fi
        done
        ;;

    6)
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│            🌀 INFRASTRUCTURE: REBUILD DOCKER         │${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
        echo -e "${RED}❌ Docker status: dead / failed (Result: exit-code)${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
        echo -e "${WHITE}[LOG] Menginstal ulang package utama Docker tanpa merusak OS induk.${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Paksa install ulang komponen internal Docker? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "\n${BLUE}[+] Mengunduh & menimpa binary file Docker Engine...${NC}"
                sudo apt-get install --reinstall docker-ce docker-ce-cli containerd.io -y
                sudo systemctl daemon-reload && sudo systemctl enable --now docker
                echo -e "${GREEN}[✔] SUCCESS: Engine Docker berhasil di-rebuild!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Invalid Choice! Ketik y atau n.${NC}"
            fi
        done
        ;;

    7)
        # ========================================================
        #  🚨 INTEGRASI MENU BARU: AUTOMATIC SCAN & BANTAI HAMA
        # ========================================================
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│     🚨 SYSTEM INVESTIGATION REPORT (RAFZ TOOLKIT)    │${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
        
        echo -e "${PURPLE}[1] MONITORING KONDISI DISK REAL-TIME:${NC}"
        df -h / | awk 'NR==2 {print " • Total Size : " $2 "\n • Terpakai   : " $3 "\n • Tersedia   : " $4 "\n • Persentase : " $5}'
        echo -e ""
        
        echo -e "${PURPLE}[2] MENCARI BIANG KEROK RAKUS DI STORAGE VOLUMES...${NC}"
        TARGET_PATH=$(du -sh /var/lib/pterodactyl/volumes/* 2>/dev/null | sort -hr | head -n 1)
        
        if [ -z "$TARGET_PATH" ]; then
            echo -e "${RED} • [!] Gagal melacak folder data server di direktori /volumes/.${NC}"
            tunggu_enter ; continue
        fi
        
        SIZE=$(echo "$TARGET_PATH" | awk '{print $1}')
        FOLDER=$(echo "$TARGET_PATH" | awk '{print $2}')
        UUID=$(basename "$FOLDER")
        SHORT_UUID=${UUID:0:8}
        
        echo -e " • Terbanyak  : ${RED}$SIZE${NC}"
        echo -e " • Direktori  : ${DARK}$FOLDER${NC}"
        echo -e ""
        
        echo -e "${PURPLE}[3] SINKRONISASI COCHING DATA KE KERNEL DATABASE PANEL:${NC}"
        echo -e "${RED}------------------------------------------------──────${NC}"
        
        # Pengecekan data di DB MariaDB/MySQL
        DB_CHECK=$(sudo mysql -u root -e "USE panel; SELECT s.id FROM servers s WHERE s.uuid LIKE '$SHORT_UUID%';" 2>/dev/null)
        
        if [ -z "$DB_CHECK" ]; then
            echo -e "${YELLOW} [!] ID Server tidak ditemukan di DB. Server kemungkinan hantu (sudah di-delete panel).${NC}"
            echo -e "${RED}------------------------------------------------──────${NC}"
            
            # Sub-opsi jika databasenya sudah hilang tapi filenya masih nimbun giga-gigaan
            while true; do
                echo -ne "${YELLOW}[?] Folder yatim piatu terdeteksi. Bersihkan paksa direktorinya? (y/n): ${NC}"
                read -r hapus_yatim
                if [[ "$hapus_yatim" =~ ^[Yy]$ ]]; then
                    sudo rm -rf "$FOLDER"
                    echo -e "${GREEN}[✔] SUCCESS: Folder sisa hantu dibabat bersih!${NC}"
                    break
                elif [[ "$hapus_yatim" =~ ^[Nn]$ ]]; then
                    break
                fi
            done
            tunggu_enter ; continue
        fi
        
        # Jalankan query SQL premium untuk menampilkan tabel pelaku secara rapi
        sudo mysql -u root -e "USE panel; SELECT s.id AS 'ID Server', s.name AS 'Nama Server', u.username AS 'Username', u.email AS 'Email Pelaku', s.uuid AS 'UUID Lengkap' FROM servers s JOIN users u ON s.owner_id = u.id WHERE s.uuid LIKE '$SHORT_UUID%';"
        echo -e "${RED}------------------------------------------------──────${NC}"
        echo -e "${GREEN}[INFO] Sinkronisasi 100% Cocok! Pelaku pelanggaran disk berhasil ditandai.${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
        echo -e ""
        
        # Prompt konfirmasi sakral bin kocak titipan Rafz
        echo -e "${YELLOW}⚠️  PERTANYAAN SAKRAL INDUK KERNEL:${NC}"
        echo -ne "${WHITE}[?] Lu yakin mau delete hama kill berkantong ${RED}$SIZE${WHITE} ini? (y/n): ${NC}"
        read -r PILIHAN
        
        case "$PILIHAN" in
            [yY][eE][sS]|[yY])
                echo -e "\n${BLUE}[+] Memulai ritual pembantaian kontainer secara masif...${NC}"
                
                # Eksekusi rantai command sakti agar tidak merusak relasi sinkronisasi
                sudo docker kill "$UUID" 2>/dev/null && \
                sudo docker rm "$UUID" 2>/dev/null && \
                sudo rm -rf "$FOLDER" && \
                sudo mysql -u root -e "USE panel; DELETE FROM servers WHERE uuid LIKE '$SHORT_UUID%';" 2>/dev/null && \
                sudo systemctl restart wings && \
                echo -e "\n${GREEN}[✔] LUNAS! Hama dengan ID awal $SHORT_UUID diberantas total! Node kembali sehat.🚀${NC}"
                ;;
                
            [nN][oO]|[nN])
                echo -e "\n${RED}Anjirlah lu milih No... 🗿🗿🗿${NC}"
                echo -e "${YELLOW}Duksh... Udah tahu VPS-nya megap-megap malah dipelihara hamanya wkwkwk. Bebas dah, Rafz! ${NC}\n"
                ;;
                
            *)
                echo -e "\n${RED}[!] Input ghoib detected! Pembantaian dibatalkan sistem.${NC}\n"
                ;;
        esac
        tunggu_enter
        ;;

    8)
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│         📥 CORE CORE: CORE CORE ARCH COMPILER       │${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
        echo -e "${YELLOW}[INFO] Menjalankan curl se-installer untuk setup Pterodactyl.${NC}"
        echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
        echo -e ""
        while true; do
            echo -ne "${YELLOW}[?] Tarik repositori & jalankan installer script? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                if ! command -v curl &> /dev/null; then
                    echo -e "${BLUE}[+] Paket curl tidak ada, menginstall curl via APT...${NC}"
                    apt-get update && apt-get install -y curl
                fi
                echo -e "${GREEN}[+] Booting installer script... GASSING-SPEED RUN! 🚀${NC}\n"
                bash <(curl -s https://pterodactyl-installer.se)
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                break
            else
                echo -e "${RED}[!] Invalid Choice! Ketik y atau n.${NC}"
            fi
        done
        ;;
esac
done
