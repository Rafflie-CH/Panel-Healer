#!/bin/bash

# Warna buat tampilan biar keren
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Pastikan script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Tolong jalankan script ini sebagai root (pake sudo atau masuk ke akun root dulu)!${NC}"
  exit 1
fi

# Fungsi jeda biar user harus masukin X/x buat balik ke menu utama
tunggu_enter() {
    echo -e ""
    echo -e "${YELLOW}======================================================${NC}"
    while true; do
        read -p "Ketik [X] lalu tekan ENTER untuk kembali ke menu utama: " jeda
        if [[ "$jeda" =~ ^[Xx]$ ]]; then
            break
        fi
        echo -e "${RED}Input salah! Harus ketik huruf X atau x bro.${NC}"
    done
}

# Menggunakan loop 'while true' agar menu terus berulang sampai user milih keluar
while true; do
clear
echo -e "${BLUE}======================================================${NC}"
echo -e "${PURPLE}           ⚡ PANEL HEALER BY RAFZ ⚡                 ${NC}"
echo -e "${BLUE}        Ultimate VPS Toolkit & Troubleshooting        ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo -e "${YELLOW}Silakan pilih opsi menu di bawah ini:${NC}"
echo -e ""
echo -e "${GREEN}1.${NC} FIX DPKG LOCK (Error gembok update apt / dpkg)"
echo -e "${GREEN}2.${NC} DEEP CLEAN PTERODACTYL (Wipe total system - Buat Ulang dari Nol)"
echo -e "${GREEN}3.${NC} QUICK CLEAN DISK (Penyimpanan penuh / Disk 100% / File Sampah Bengkak)"
echo -e "${GREEN}4.${NC} MANUAL WIPE DATA GAME & SQL (Hapus sisa server game & DB raksasa)"
echo -e "${GREEN}5.${NC} FIX DOCKER SOCKET ERROR (Error Wings ga bisa konek ke daemon/docker)"
echo -e "${GREEN}6.${NC} FORCE REINSTALL DOCKER (Docker mati total / Status Dead / Corrupted)"
echo -e "${GREEN}7.${NC} TOOLS CEK KESEHATAN VPS (Cek Storage, Folder Ter-rakus, & Status Docker)"
echo -e "${PURPLE}8.${NC} INSTALL PTERODACTYL PANEL (Otomatis Jalankan Script Installer)"
echo -e "${RED}X.${NC} Keluar dari Script"
echo -e "${BLUE}======================================================${NC}"

# Loop validasi menu jika kosong atau salah ketik
while true; do
    read -p "Masukkan pilihan lu [1-8 atau X]: " pilihan
    if [[ -z "$pilihan" ]]; then
        echo -e "${RED}[!] Pilihan kosong bro! Silakan masukkan opsi yang bener.${NC}"
    elif [[ "$pilihan" =~ ^[Xx]$ ]] || [ "$pilihan" = "0" ]; then
        echo -e "${GREEN}Thank you udah pake Panel Healer by Rafz. Keluar...${NC}"
        exit 0
    elif [[ "$pilihan" =~ ^[1-8]$ ]]; then
        break
    else
        echo -e "${RED}[!] Opsi tidak valid! Pilihannya cuma [1-8 atau X].${NC}"
    fi
done

case $pilihan in
    1)
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[CONTOH ERROR NYA]:${NC}"
        echo -e "${RED}❌ E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process...${NC}"
        echo -e "${RED}❌ E: Unable to acquire the dpkg frontend lock...${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[INFO] Menghapus gembok instalasi (lock) sisa proses background, memperbaiki dpkg yang tertunda, dan refresh repository.${NC}"
        echo -e ""
        while true; do
            read -p "Lu pilih opsi 1, apakah lu yakin? (y/n atau x untuk kembali): " konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Menjalankan perbaikan...${NC}"
                rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock && dpkg --configure -a && apt clean && apt update
                echo -e "${GREEN}\n[SUKSES] DPKG Berhasil di-fix! Silakan gas lagi script installer lu.${NC}"
                tunggu_enter
                break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                echo -e "${RED}Proses dibatalkan.${NC}"
                break
            else
                echo -e "${RED}Input salah! Jawab dengan y (ya), n (tidak), atau x (kembali).${NC}"
            fi
        done
        ;;
        
    2)
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[KONDISI PENGGUNAAN]:${NC}"
        echo -e "${RED}⚠️  Gunakan ini saat installer panel error/gagal tengah jalan dan lu mau reset total VPS biar bersih gils tanpa harus instal ulang OS / reboot VPS.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${RED}[PERINGATAN] Opsi ini akan menghapus TOTAL seluruh instalasi Pterodactyl, Wings, Nginx, Docker Container, dan Database MySQL di VPS ini!${NC}"
        echo -e ""
        while true; do
            read -p "Lu pilih DEEP CLEAN PTERODACTYL, apakah lu yakin banget? (y/n atau x untuk kembali): " konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Memulai pembersihan total (Wipe out)... Mohon tunggu, proses ini memakan waktu.${NC}"
                sudo systemctl stop wings pteroq nginx mysql mariadb redis-server 2>/dev/null
                sudo killall -9 nginx mariadb mysqld 2>/dev/null
                sudo systemctl disable wings pteroq nginx mysql mariadb redis-server 2>/dev/null
                sudo rm -rf /etc/systemd/system/wings.service /etc/systemd/system/pteroq.service
                sudo docker stop $(sudo docker ps -a -q) 2>/dev/null
                sudo docker rm $(sudo docker ps -a -q) 2>/dev/null
                sudo docker rmi $(sudo docker images -q) 2>/dev/null
                sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null
                sudo rm -rf /var/lib/docker /etc/docker /var/www/pterodactyl /etc/pterodactyl /var/log/pterodactyl /etc/wings
                sudo apt-get purge -y nginx* mysql-* mariadb-* php8.3* php8.2* php-fpm* redis-* 2>/dev/null
                sudo apt-get autoremove -y
                sudo apt-get clean
                sudo rm -rf /var/lib/mysql /var/lib/mariadb /etc/mysql /var/log/nginx /etc/nginx /var/lib/redis
                sudo mkdir -p /usr/local/bin && sudo chmod 755 /usr/local/bin
                sudo systemctl daemon-reload && sudo systemctl reset-failed
                echo -e "\n\033[1;32m[SUKSES TOTAL] VPS Bersih & Sistem Reset! Langsung Gas Installer.\033[0m\n"
                tunggu_enter
                break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                echo -e "${RED}Proses dibatalkan.${NC}"
                break
            else
                echo -e "${RED}Input salah! Jawab dengan y (ya), n (tidak), atau x (kembali).${NC}"
            fi
        done
        ;;

    3)
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[CONTOH ERROR NYA]:${NC}"
        echo -e "${RED}❌ Error: No space left on device${NC}"
        echo -e "${RED}❌ Panel ngeblank / Error 500 karena database mati mendadak saat penyimpanan full 100%.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[INFO] Menghapus log sistem tua (.gz) dan mengosongkan log aktif tanpa menghapus data project atau server game.${NC}"
        echo -e ""
        while true; do
            read -p "Lu pilih QUICK CLEAN DISK, apakah lu yakin? (y/n): " konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Membersihkan cache dan log...${NC}"
                sudo apt-get clean && sudo find /var/log -type f -regex '.*\.gz$\|.*\.1$' -delete && sudo find /var/log -type f -exec truncate -s 0 {} + && sudo rm -rf /tmp/*
                echo -e "${GREEN}\n[SUKSES] Quick Clean selesai! Storage VPS lu dapet napas tambahan.${NC}"
                tunggu_enter
                break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                echo -e "${RED}Proses dibatalkan.${NC}"
                break
            else
                echo -e "${RED}Input salah! Jawab dengan y (ya), n (tidak), atau x (kembali).${NC}"
            fi
        done
        ;;

    4)
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[KONDISI PENGGUNAAN]:${NC}"
        echo -e "${RED}⚠️  Gunakan ini kalau disk MASIH PENUH padahal lu udah uninstall panel pake script resmi. Command ini ngebabat paksa folder data game raksasa yang tertinggal.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${RED}[PERINGATAN] Opsi ini menghapus paksa folder data game (/var/lib/pterodactyl), web panel, Nginx vhost, dan database server (MariaDB/MySQL).${NC}"
        echo -e ""
        while true; do
            read -p "Lu pilih MANUAL WIPE DATA GAME & SQL, apakah lu yakin? (y/n): " konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Menghapus data game raksasa dan database...${NC}"
                sudo systemctl stop wings pteroq && sudo rm -rf /var/lib/pterodactyl /etc/pterodactyl /var/www/pterodactyl /etc/nginx/sites-enabled/pterodactyl.conf /etc/systemd/system/wings.service /etc/systemd/system/pteroq.service /var/log/pterodactyl && sudo apt-get purge -y mariadb-server mysql-server && sudo apt-get autoremove -y
                echo -e "${GREEN}\n[SUKSES] Data game raksasa & database berhasil dikosongkan total!${NC}"
                tunggu_enter
                break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                echo -e "${RED}Proses dibatalkan.${NC}"
                break
            else
                echo -e "${RED}Input salah! Jawab dengan y (ya), n (tidak), atau x (kembali).${NC}"
            fi
        done
        ;;

    5)
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[CONTOH ERROR NYA]:${NC}"
        echo -e "${RED}❌ Error response from daemon: Dialogue /var/run/docker.sock: bind: address already in use${NC}"
        echo -e "${RED}❌ Failed to listen on Docker Socket (nyangkut pas mati lampu/disk 100%).${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[INFO] Memperbaiki error 'Failed to listen on Docker Socket' dengan me-restart service dan membersihkan file socket lama.${NC}"
        echo -e ""
        while true; do
            read -p "Lu pilih FIX DOCKER SOCKET ERROR, apakah lu yakin? (y/n): " konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Mereset Docker Socket...${NC}"
                sudo systemctl stop docker.socket && sudo systemctl stop docker && sudo rm -f /var/run/docker.sock && sudo systemctl start docker.socket && sudo systemctl start docker
                echo -e "${GREEN}\n[SUKSES] Docker Socket berhasil diperbaiki! Cek status docker lu sekarang.${NC}"
                tunggu_enter
                break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                echo -e "${RED}Proses dibatalkan.${NC}"
                break
            else
                echo -e "${RED}Input salah! Jawab dengan y (ya), n (tidak), atau x (kembali).${NC}"
            fi
        done
        ;;

    6)
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[CONTOH ERROR NYA]:${NC}"
        echo -e "${RED}❌ Docker status: dead / failed (Result: exit-code)${NC}"
        echo -e "${RED}❌ Docker bener-bener rusak parah di bagian komponen internalnya akibat crash sistem.${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[INFO] Menginstal ulang package utama Docker tanpa merusak OS induk.${NC}"
        echo -e ""
        while true; do
            read -p "Lu pilih FORCE REINSTALL DOCKER, apakah lu yakin? (y/n): " konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Mengunduh dan reinstall Docker...${NC}"
                sudo apt-get install --reinstall docker-ce docker-ce-cli containerd.io && sudo systemctl daemon-reload && sudo systemctl enable --now docker
                echo -e "${GREEN}\n[SUKSES] Docker berhasil di-reinstall paksa dan dinyalakan kembali!${NC}"
                tunggu_enter
                break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                echo -e "${RED}Proses dibatalkan.${NC}"
                break
            else
                echo -e "${RED}Input salah! Jawab dengan y (ya), n (tidak), atau x (kembali).${NC}"
            fi
        done
        ;;

    7)
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${PURPLE}           📊 TOOLS CEK KESEHATAN VPS                 ${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[1] Sisa Penyimpanan VPS (df -h):${NC}"
        df -h
        echo -e ""
        echo -e "${YELLOW}[2] Top 5 Folder Paling Rakus / Makan Space:${NC}"
        du -sh /* 2>/dev/null | sort -hr | head -n 5
        echo -e ""
        echo -e "${YELLOW}[3] Kondisi Layanan Docker (Harus active/running):${NC}"
        systemctl status docker | grep -E "Active:|Loaded:"
        tunggu_enter
        ;;

    8)
        clear
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${PURPLE}        📥 AUTOMATIC PTERODACTYL INSTALLER            ${NC}"
        echo -e "${BLUE}======================================================${NC}"
        echo -e "${YELLOW}[INFO] Opsi ini akan otomatis menjalankan script installer Pterodactyl resmi via se-installer.${NC}"
        echo -e ""
        while true; do
            read -p "Apakah lu yakin mau jalanin installer Pterodactyl sekarang? (y/n): " konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                if ! command -v curl &> /dev/null; then
                    echo -e "${YELLOW}[INFO] curl tidak ditemukan, menginstall curl terlebih dahulu...${NC}"
                    apt-get update && apt-get install -y curl
                fi
                echo -e "${GREEN}Menjalankan installer... GASS!🚀${NC}"
                echo -e ""
                bash <(curl -s https://pterodactyl-installer.se)
                tunggu_enter
                break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then
                echo -e "${RED}Proses dibatalkan.${NC}"
                break
            else
                echo -e "${RED}Input salah! Jawab dengan y (ya), n (tidak), atau x (kembali).${NC}"
            fi
        done
        ;;
esac
done
