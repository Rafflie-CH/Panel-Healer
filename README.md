<!--
  Panel-Healer README — dokumentasi penuh
  Repo: https://github.com/Rafflie-CH/Panel-Healer
  Brand: RAFZHOST × DEKZYMARKET
-->

<div align="center">

# ⚡ Panel-Healer
### Toolkit Pterodactyl All-in-One — **RAFZHOST × DEKZYMARKET**

<img src="https://img.shields.io/badge/status-stable-brightgreen?style=for-the-badge" alt="stable" />
<img src="https://img.shields.io/badge/godmode-v3.9-purple?style=for-the-badge" alt="godmode" />
<img src="https://img.shields.io/badge/healer-v3.5-cyan?style=for-the-badge" alt="healer" />

<br/>

[![GitHub stars](https://img.shields.io/github/stars/Rafflie-CH/Panel-Healer?style=for-the-badge&logo=github&color=purple)](https://github.com/Rafflie-CH/Panel-Healer/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Rafflie-CH/Panel-Healer?style=for-the-badge&logo=github&color=blue)](https://github.com/Rafflie-CH/Panel-Healer/network/members)
[![GitHub issues](https://img.shields.io/github/issues/Rafflie-CH/Panel-Healer?style=for-the-badge)](https://github.com/Rafflie-CH/Panel-Healer/issues)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-4%2B-1f425f?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Pterodactyl](https://img.shields.io/badge/Pterodactyl-Panel%20%2B%20Wings-98FB98?style=for-the-badge)](https://pterodactyl.io/)

**Install · Perbaiki · Kelola panel game server (Pterodactyl) di VPS — tanpa harus jago coding.**

<br/>

### 📬 Hubungi kami (Telegram)

| Akun | Link | Untuk apa |
|------|------|-----------|
| **@rafzbotz** | [t.me/rafzbotz](https://t.me/rafzbotz) | Akun utama — **lapor error / tanya teknis** |
| **@rafzch** | [t.me/rafzch](https://t.me/rafzch) | Channel testimoni, produk dijual, info promo |
| **@rafzhost** | [t.me/rafzhost](https://t.me/rafzhost) | Channel jam kerja, partner, pengumuman |

[![Telegram Botz](https://img.shields.io/badge/Telegram-@rafzbotz_Lapor_Error-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/rafzbotz)
[![Channel CH](https://img.shields.io/badge/Channel-@rafzch-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/rafzch)
[![Channel Host](https://img.shields.io/badge/Channel-@rafzhost-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/rafzhost)

> Kalau script error: kirim ke **@rafzbotz** — sertakan screenshot + isi `/root/ptero_install.log` (potong bagian password/token).

<br/>

---

### 📋 Salin perintah (satu per satu — siap tempel di terminal)

</div>

#### 1️⃣ Install panel penuh (GodMode)

[![Salin GodMode](https://img.shields.io/badge/📋_Salin_perintah-GodMode_Install-purple?style=for-the-badge)](https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)
```

#### 2️⃣ Perbaiki / heal panel yang sudah ada (Healer)

[![Salin Healer](https://img.shields.io/badge/📋_Salin_perintah-Panel_Healer-cyan?style=for-the-badge)](https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/healer.sh)

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/healer.sh)
```

#### 3️⃣ VPS Tunnelling (repo terpisah)

[![Salin Tunnel](https://img.shields.io/badge/📋_Salin_perintah-VPS_Tunnelling-blue?style=for-the-badge)](https://raw.githubusercontent.com/Rafflie-CH/vps-tunelling/main/bash.sh)

```bash
bash <(curl -s https://raw.githubusercontent.com/Rafflie-CH/vps-tunelling/main/bash.sh)
```

<div align="center">

**Cara pakai perintah di atas (pemula):**  
1. Buka terminal VPS (SSH) sebagai **root**  
2. **Blok kode** di atas → klik ikon copy di kanan blok (GitHub) atau seleksi manual → salin  
3. Tempel di terminal → tekan **Enter**  
4. Ikuti pertanyaan di layar

[📖 Daftar isi](#-daftar-isi) ·
[🎓 Tutorial pemula 0→panel](#-tutorial-pemula-dari-nol-sampai-panel-hidup) ·
[📜 Changelog](#-changelog) ·
[🛣 Progress](#-progress--roadmap)

</div>

---

## 📑 Daftar Isi

1. [Apa itu proyek ini?](#-apa-itu-proyek-ini)
2. [Istilah yang wajib dipahami](#-istilah-yang-wajib-dipahami-baca-ini-dulu)
3. [Struktur file di repo](#-struktur-file-di-repo)
4. [Persyaratan VPS & DNS](#-persyaratan-vps--dns)
5. [Tutorial pemula: dari nol sampai panel hidup](#-tutorial-pemula-dari-nol-sampai-panel-hidup)
6. [GodMode — installer lengkap](#-godmode--installer-lengkap-v39)
7. [Healer — toolkit perbaikan](#-healer--toolkit-perbaikan-v35)
8. [bot.zip — bot Telegram Create Panel](#-botzip--bot-telegram-create-panel)
9. [VPS Tunnelling](#-vps-tunnelling)
10. [Uninstall & reset](#-uninstall--reset)
11. [Mode otomatis (tanpa ketik interaktif)](#-mode-otomatis-tanpa-ketik-interaktif)
12. [File hasil install & log](#-file-hasil-install--log)
13. [Contoh sesi install end-to-end](#-contoh-sesi-install-end-to-end)
14. [FAQ & error umum](#-faq--error-umum)
15. [Keamanan](#-keamanan)
16. [Progress & roadmap](#-progress--roadmap)
17. [Changelog](#-changelog)
18. [Kontak & dukungan](#-kontak--dukungan)
19. [Credits](#-credits)

---

## 🎯 Apa itu proyek ini?

**Panel-Healer** adalah kumpulan **script bash** (perintah otomatis di Linux) untuk:

| Tujuan | Script | Satu kalimat |
|--------|--------|----------------|
| **Pasang** panel game server baru | `godmode.sh` | Satu perintah → Panel + Wings + node + egg (+ bot opsional) |
| **Perbaiki** panel yang rusak / VPS bermasalah | `healer.sh` | Menu angka: bersihkan, fix Docker, anti-spam, dll. |
| **Bot Telegram** buat server otomatis | `bot.zip` | User chat bot → server Pterodactyl terbuat |
| **Tunnel** (repo lain) | `vps-tunelling` | Bantu expose/tunnel layanan VPS |

Semua dijalankan di **VPS Linux** (komputer sewa di cloud), biasanya lewat **SSH** (remote terminal).

**Bukan** aplikasi Windows/Android yang di-double-click.  
**Bukan** cPanel hosting klasik.  
“**CPanel**” di bot = **Create Panel** (membuat server di Pterodactyl lewat Telegram).

---

## 📚 Istilah yang wajib dipahami (baca ini dulu)

| Istilah | Arti sederhana |
|---------|----------------|
| **VPS** | Komputer sewa di internet (DigitalOcean, Contabo, dll.) yang kamu kendalikan 24 jam |
| **SSH** | Cara “masuk” ke VPS dari laptop/HP lewat terminal (contoh app: Termius, Server Auditor, PuTTY) |
| **Root** | Akun super-admin di Linux. Script ini **wajib root** |
| **Domain** | Nama seperti `panel.namamu.com` yang diarahkan ke IP VPS |
| **DNS A record** | Pengaturan di penjual domain: nama → angka IP VPS |
| **Pterodactyl Panel** | Website admin untuk kelola server game/bot |
| **Wings** | Program di VPS yang menjalankan server (Docker) atas perintah panel |
| **Docker** | Teknologi “kotak” isolasi tempat server game/bot berjalan |
| **Allocation** | Kombinasi IP + port (contoh `1.2.3.4:25565`) untuk server |
| **Egg** | Template cara menjalankan server (startup, Docker image, variabel) |
| **PLTA** | API key tipe Application (panel → buat node/server lewat API) |
| **PLTC** | API key tipe Client (kontrol power start/stop server) |
| **Let's Encrypt / SSL** | Sertifikat HTTPS gratis agar gembok hijau di browser |
| **One-liner** | Satu baris perintah yang mengunduh + menjalankan script |

Kalau istilah di atas sudah kebayang, lanjut tutorial.

---

## 📁 Struktur file di repo

```text
https://github.com/Rafflie-CH/Panel-Healer
│
├── godmode.sh     ← Installer utama (v3.9)
├── healer.sh      ← Toolkit perbaikan (v3.5)
├── bot.zip        ← Source bot Telegram (JANGAN di-extract di GitHub)
├── test.sh        ← Util / percobaan (opsional)
└── README.md      ← Dokumentasi ini
```

| File | Apa isinya | Kapan dipakai |
|------|------------|----------------|
| **godmode.sh** | Ratusan baris bash: cek OS, install panel, SSL, Wings, API, egg, bot, uninstall | VPS baru atau reinstall |
| **healer.sh** | Menu interaktif perbaikan + auto-diagnosa | Panel sudah ada tapi error / penuh / stuck |
| **bot.zip** | Node.js bot (index.js, settings.js, plugins, …) | GodMode opsi “pasang bot” = y, atau manual |
| **test.sh** | Script bantu uji | Developer / advanced |

**Aturan bot.zip:** file di repo harus tetap **`.zip` utuh**.  
GodMode akan mengunduh/extract sendiri ke folder server.

---

## 📋 Persyaratan VPS & DNS

### VPS

| Item | Minimal | Disarankan |
|------|---------|------------|
| OS | Ubuntu **22.04** atau **24.04** | 24.04 |
| CPU | 2 vCPU | 4 vCPU |
| RAM | 2 GB | 4 GB+ |
| Disk | 20 GB bebas | 40 GB+ SSD |
| Akses | Login **root** | root + password/SSH key |
| Firewall | Buka **80, 443, 8080, 2022** | + port game yang dipakai |

Cek OS setelah login SSH:

```bash
cat /etc/os-release
whoami
# harus cetak: root
```

### Domain & DNS (wajib sebelum GodMode install)

Kamu butuh **2 nama** (boleh subdomain):

| Peran | Contoh nama | Tipe DNS | Isi |
|-------|-------------|----------|-----|
| Panel (website admin) | `panel.contoh.com` | **A** | IP publik VPS |
| Node (Wings / daemon) | `node.contoh.com` | **A** | IP publik VPS **yang sama** |

Cek dari laptop (atau dari VPS):

```bash
dig +short panel.contoh.com @8.8.8.8
dig +short node.contoh.com @8.8.8.8
```

Hasilnya harus **sama** dengan IP VPS.  
Kalau masih kosong / IP lain → **jangan** lanjut install; tunggu propagasi DNS.

### Opsional (untuk bot Telegram)

1. Buat bot di [@BotFather](https://t.me/BotFather) → dapat **token** `123456:AAF...`
2. Ambil ID angka kamu di [@userinfobot](https://t.me/userinfobot)
3. (Opsional) Cloudflare Zone ID + API Token untuk subdomain otomatis

---

## 🎓 Tutorial pemula: dari nol sampai panel hidup

Ikuti **urut**. Jangan loncat.

### Langkah A — Sewa VPS & catat IP

1. Beli VPS Ubuntu 22.04/24.04.
2. Catat: **IP** (contoh `152.42.223.223`), **password root** (atau SSH key).

### Langkah B — Arahkan domain

1. Masuk ke tempat beli domain (Cloudflare, Namecheap, Niagahoster, dll.).
2. Buat 2 record **A**:
   - `panel` → IP VPS  
   - `node` → IP VPS  
3. Tunggu sampai `dig` menampilkan IP yang benar.

### Langkah C — Masuk VPS lewat SSH

**Dari HP (Server Auditor / Termius / JuiceSSH):**

1. New connection → Host = IP VPS, User = `root`, Password = password VPS.
2. Connect.

**Dari Windows (PuTTY / Windows Terminal):**

```text
ssh root@IP_VPS
```

Kalau ditanya fingerprint, ketik `yes`.

### Langkah D — Jadi root (jika belum)

```bash
sudo su
whoami
```

Harus keluar: `root`.

### Langkah E — Jalankan GodMode

Salin **hanya** perintah ini (satu baris):

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)
```

Tempel di terminal → Enter.

Artinya:

- `curl` mengunduh script dari GitHub  
- `bash` menjalankannya langsung  
- Tidak perlu `git clone` manual  

### Langkah F — Pilih menu

```text
[1] Install Panel + Wings + Egg (God Mode)   ← pilih ini
[2] … uninstall …
```

Ketik `1` lalu Enter.

### Langkah G — Jawab pertanyaan

Contoh isian:

```text
Domain Panel     : panel.contoh.com
Domain Node      : node.contoh.com
Email Admin      : emailkamu@gmail.com
Username Admin   : admin
Nama Depan       : Admin
Nama Belakang    : Rafz
Password Admin   : (buat password kuat, ingat!)
Alias Allocation : NODE-01
Bot CPanel?      : n          (ketik y jika mau bot)
```

- **Enter** saja = pakai nilai default di dalam kurung `[...]`.
- Domain panel dan node **tidak boleh sama**.

### Langkah H — Tunggu

Proses bisa **10–30 menit** (unduh paket, panel, Docker, SSL).  
Jangan tutup SSH.  
Kalau putus, cek log:

```bash
tail -100 /root/ptero_install.log
```

### Langkah I — Selesai: login panel

Di akhir script akan tampil URL + username + password.  
Buka browser:

```text
https://panel.contoh.com
```

Login dengan username/password yang kamu isi.

### Langkah J — Kalau error

1. Screenshot terminal.  
2. Salin 30–50 baris terakhir:

```bash
tail -50 /root/ptero_install.log
```

3. Kirim ke Telegram **[@rafzbotz](https://t.me/rafzbotz)** (sensor password & token bot).

### Langkah K — Panel sudah ada tapi bermasalah

Jangan install ulang dulu. Jalankan Healer:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/healer.sh)
```

Pilih menu sesuai keluhan (lihat tabel Healer di bawah).

---

## 🚀 GodMode — Installer lengkap (v3.9)

**File:** [godmode.sh](https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)

### Fitur (daftar lengkap)

| # | Fitur | Penjelasan |
|---|--------|------------|
| 1 | Panel + Wings 1 VPS | Install web panel + daemon di mesin yang sama |
| 2 | Location + Node + Allocation | Otomatis lewat API setelah panel hidup |
| 3 | Egg Nusantara Ultimate v9 | Template PM2 multi-bot, SSH, Yarn/NPM, Python, Cloudflared |
| 4 | Proteksi egg | Non-root sulit export / lihat startup mentah |
| 5 | SSL Unified | 1 sertifikat Let's Encrypt untuk domain panel **dan** node |
| 6 | Antisipasi rate limit LE | Fallback staging/self-signed + cron retry tiap 6 jam |
| 7 | Wings native TLS port 8080 | Daemon HTTPS langsung, tanpa reverse-proxy 443 khusus node |
| 8 | Bot Create Panel opsional | Buat server `CPANEL RAFZHOST`, extract bot.zip, isi settings.js, start |
| 9 | Menu uninstall | Reset VPS / panel only / wings only / both |
| 10 | UI berwarna | Teks warna di terminal (gaya Healer) |
| 11 | Log + file data | `/root/ptero_install.log`, `/root/rafzhost-panel-data.txt` |
| 12 | Mode ENV | Bisa dijalankan tanpa ketik (otomasi) |

### Menu saat dibuka

| Tombol | Nama | Kapan dipakai |
|--------|------|----------------|
| **1** | Install God Mode | VPS baru / pasang dari nol |
| **2** | Reset VPS (Deep Clean) | Mau hapus **semua** jejak panel/docker/nginx/db (ketik `YES`) |
| **3** | Uninstall Panel saja | Hapus website panel, DB panel, cron panel |
| **4** | Uninstall Wings saja | Hapus daemon + volume server |
| **5** | Uninstall Panel + Wings | Gabungan 3 + 4 |

### Yang ditanya saat install (menu 1)

| Urutan | Pertanyaan | Contoh | Wajib? |
|--------|------------|--------|--------|
| 1 | Domain Panel | `panel.contoh.com` | Ya |
| 2 | Domain Node | `node.contoh.com` | Ya |
| 3 | Email Admin | `admin@gmail.com` | Ya |
| 4 | Username Admin | `admin` | Ya |
| 5 | Nama Depan | `Admin` | Tidak |
| 6 | Nama Belakang | `Rafz` | Tidak |
| 7 | Password Admin | `******` | Ya |
| 8 | Alias Allocation | `NODE-JKT-01` | Tidak (default nama node) |
| 9 | Pasang bot CPanel? | `y` / `n` | Tidak |
| 10 | Token bot | dari BotFather | Jika 9 = y |
| 11 | ID Owner Telegram | angka dari userinfobot | Jika 9 = y |
| 12 | Pakai Cloudflare? | `y` / `n` | Tidak |
| 13 | Domain CF / Zone / API | — | Jika 12 = y |

**Tidak ditanya (otomatis):** hostname mesin, location `RafzHost`, IP allocation = IP VPS, port **2000–2999**.

### Urutan kerja internal (step)

| Step | Nama | Yang terjadi (bahasa manusia) |
|------|------|-------------------------------|
| 01 | Cek sistem | Pastikan Ubuntu & arsitektur didukung |
| 02 | Dependency | Install tools: curl, jq, dig, redis, dll. |
| 03 | IP VPS | Deteksi IP publik |
| 04 | DNS | Bandingkan DNS domain dengan IP VPS |
| 05 | Panel | Pasang Pterodactyl Panel + Nginx + database |
| 05c | SSL | Minta/reuse sertifikat HTTPS untuk 2 domain |
| 06 | Wings | Pasang Docker + program Wings |
| 07 | API keys | Buat PLTA & PLTC untuk admin |
| 08 | Tes API | Pastikan PLTA bisa dipanggil |
| 09 | Location | Buat lokasi di panel |
| 10 | Node | Daftarkan node (mesin ini) |
| 11 | Allocation | Siapkan rentang port 2000–2999 |
| 12 | Config Wings | Tulis `config.yml` (TLS port 8080) |
| 13 | Start Wings | Nyalakan service wings |
| 14 | Verifikasi | Cek panel bisa bicara dengan Wings |
| 15 | Egg | Import egg Nusantara v9 + pengamanan |
| 16 | Bot | (Opsional) server bot + settings + start |
| 17 | Ringkasan | Tampilkan login, kunci API, path log |

### SSL & rate limit (detail)

- Nama cert internal: **`rafzhost-ssl`** (satu cert, dua domain).
- Jika Let's Encrypt menolak (terlalu banyak request):
  - pakai staging atau self-signed sementara;
  - cron **`/usr/local/bin/rafz-ssl-retry`** mencoba lagi tiap **6 jam**.
- Paksa coba ulang manual:

```bash
sudo /usr/local/bin/rafz-ssl-retry
```

### Egg Nusantara Ultimate v9 (detail)

- Di dalam script (bukan file terpisah di repo).
- Cocok untuk bot Node multi-proses (PM2), opsi SSH, Yarn/NPM, Python, token Cloudflared.
- Setelah import: user non-root dipersulit **export egg** / menyalin startup mentah dari UI admin.

### Bot CPanel otomatis (detail step 16)

1. Cari allocation kosong (atau buat port ekstra).  
2. Buat server nama **`CPANEL RAFZHOST`**, owner = admin install.  
3. Ambil zip: `/root/bot.zip` **atau** unduh dari repo `main/bot.zip`.  
4. Extract ke volume Docker/Wings.  
5. Tulis `settings.js` (owner, domain panel, PLTA, PLTC, egg, nest, loc, CF).  
6. Tulis token ke `session/creds.json`.  
7. Tunggu install script egg (npm install) → kirim sinyal **start** (dengan retry).

---

## 🩺 Healer — Toolkit perbaikan (v3.5)

**File:** [healer.sh](https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/healer.sh)

### Cara jalankan

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/healer.sh)
```

Harus root. Tampilan berwarna; tiap buka menu ada **auto-check**.

### Auto-check saat dashboard

| Yang dicek | Kalau bermasalah | Arahkan ke menu |
|------------|------------------|-----------------|
| Banyak koneksi port 80/443 | Panel lambat / stuck | **09** |
| Banyak koneksi port 8080 | Wings kewalahan | **09** atau **07** |
| Log nginx “aborting / open socket” | Web panel putus-putus | **09** |
| Service wings mati | Server game tidak nyala | **05** / **06** |

### Menu lengkap

| Kode | Nama | Penjelasan untuk pemula | Risiko |
|------|------|-------------------------|--------|
| **01** | Fix DPKG Lock | Mengunci apt “sedang dipakai” dilonggarkan agar update bisa jalan | Rendah |
| **02** | Deep Clean Panel | **Menghapus hampir semua** panel, Docker, Nginx, database | **TINGGI** — backup dulu |
| **03** | Quick Clean Disk | Hapus log/cache sampah biar disk lega | Rendah |
| **04** | Wipe Volumes | Hapus data server game yang nyangkut di disk | Tinggi untuk data server |
| **05** | Fix Docker Socket | Perbaiki hubungan Wings ↔ Docker | Sedang |
| **06** | Reinstall Docker | Pasang ulang Docker dari nol | Sedang |
| **07** | Auto Ciduk Hama | Cari server yang menyedot resource, opsi hapus | Sedang–tinggi |
| **08** | Pterodactyl Core | Jalankan installer resmi upstream | Sedang |
| **09** | Rate Limit & Flush | Batasi spam request + bersihkan koneksi macet | Rendah |
| **X** | Keluar | Tutup toolkit | — |

Setelah selesai satu menu, biasanya diminta ketik **`X`** lalu Enter untuk kembali ke dashboard.

---

## 🤖 bot.zip — Bot Telegram Create Panel

**File:** [bot.zip](https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/bot.zip)

### Apa gunanya?

User di Telegram mengetik perintah → bot memanggil API Pterodactyl → **server baru** terbuat (ram/disk/cpu sesuai wizard).

### Isi zip (setelah di-extract)

```text
index.js         # program utama + koneksi Telegram
settings.js      # pengaturan (owner, panel, Cloudflare)
case.js          # daftar perintah bot
package.json     # daftar library Node.js
library/         # database JSON, antiflood, monitor
plugins/         # fitur tambahan (menu, tools, …)
session/         # menyimpan token bot
Dockerfile       # opsional jalan di Docker
```

### settings.js (inti)

```js
global.owner = ["ID_TELEGRAM_ANGKA"]
global.panelServer = {
  1: {
    name: "NamaTampilan",
    domain: "https://panel.contoh.com",
    apikey: "ptla_xxxx",
    capikey: "ptlc_xxxx",
    egg: "15",
    nestid: "5",
    loc: "1"
  }
}
```

GodMode mengisi ini **otomatis** jika kamu pilih pasang bot.

### Jalankan manual (tanpa GodMode)

```bash
cd /path/ke/folder-bot
nano settings.js          # edit manual
export TELEGRAM_TOKEN='token-dari-BotFather'
npm install
npm start
```

Health check (default): port **7860** → `http://IP:7860/health`

---

## 🌐 VPS Tunnelling

Repo terpisah: [Rafflie-CH/vps-tunelling](https://github.com/Rafflie-CH/vps-tunelling)

```bash
bash <(curl -s https://raw.githubusercontent.com/Rafflie-CH/vps-tunelling/main/bash.sh)
```

Pakai bila perlu tunnel/expose layanan; **bukan** pengganti GodMode/Healer.

---

## 🗑️ Uninstall & reset

### Lewat menu GodMode

Jalankan godmode → pilih **2 / 3 / 4 / 5**.

| Opsi | Efek |
|------|------|
| 2 Reset VPS | Hapus panel, wings, docker, nginx, mariadb/mysql, redis, sisa file RAFZ — konfirmasi **`YES`** |
| 3 Panel | Hapus panel + DB `panel` + nginx site panel |
| 4 Wings | Hapus wings + `/var/lib/pterodactyl` + prune docker |
| 5 Both | 4 kemudian 3 |

### Lewat environment

```bash
GODMODE_ACTION=rm_panel bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)
GODMODE_ACTION=rm_wings bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)
GODMODE_ACTION=rm_both  bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)
```

`reset_vps` tetap meminta ketik **YES** agar tidak kehapus tanpa sengaja.

---

## ⚙️ Mode otomatis (tanpa ketik interaktif)

Cocok untuk otomasi / reinstall scripted:

```bash
export NONINTERACTIVE=1
export PANEL_DOMAIN=panel.contoh.com
export NODE_DOMAIN=node.contoh.com
export ADMIN_EMAIL=admin@contoh.com
export ADMIN_USERNAME=admin
export ADMIN_FIRSTNAME=Admin
export ADMIN_LASTNAME=Rafz
export ADMIN_PASSWORD='GantiPasswordIni!'
export ALLOC_ALIAS='NODE-01'
export INSTALL_CPANEL_BOT=n
# jika bot:
# export INSTALL_CPANEL_BOT=y
# export BOT_TOKEN='123:AAF...'
# export BOT_OWNER_ID='7848360765'
# export BOT_CF_ENABLE=n

bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)
```

---

## 📄 File hasil install & log

| Lokasi | Isi | Catatan |
|--------|-----|---------|
| `/root/ptero_install.log` | Log seluruh proses install | Kirim potongan ini saat lapor error |
| `/root/rafzhost-panel-data.txt` | URL, user, password, PLTA, PLTC, ID | **Rahasia** — `chmod 600` |
| `/var/log/rafzhost-ssl-retry.log` | Log percobaan ulang SSL | |
| `/etc/pterodactyl/config.yml` | Konfigurasi Wings | |
| `/var/www/pterodactyl` | Kode panel | |
| `/var/lib/pterodactyl/volumes/...` | File per server (termasuk bot) | |

Lihat data login lagi:

```bash
cat /root/rafzhost-panel-data.txt
```

---

## 🧪 Contoh sesi install end-to-end

```text
$ ssh root@152.42.223.223
$ bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)

  MENU → 1

  Domain Panel: myconsole.rafzhost.my.id
  Domain Node:  node-myconsole.rafzhost.my.id
  Email:        admin@gmail.com
  Username:     admin
  Password:     ********
  Alias:        FIXZZ-MARKET
  Bot CPanel?:  y
  Token:        8727...:AAF...
  Owner ID:     7848360765
  Cloudflare?:  y (isi zone/key atau data uji)

  ... (step 01–17) ...

  INSTALLASI SELESAI
  URL      https://myconsole.rafzhost.my.id
  Username admin
  Password ********
  PLTA     ptla_...
  PLTC     ptlc_...
  Egg ID   15
  Alloc    152.42.223.223:2000-2999 (FIXZZ-MARKET)
```

Browser → login panel → (opsional) cek server **CPANEL RAFZHOST** → chat bot Telegram.

---

## ❓ FAQ & error umum

<details>
<summary><b>Permission denied / bukan root</b></summary>

```bash
sudo su
whoami   # harus root
```

</details>

<details>
<summary><b>DNS Panel tidak match</b></summary>

Record A belum ke IP VPS. Cek:

```bash
dig +short DOMAIN_PANEL @8.8.8.8
curl -4 ifconfig.me
```

Samakan, tunggu propagasi.

</details>

<details>
<summary><b>Let's Encrypt rate limit / cert gagal</b></summary>

Script akan fallback. Nanti:

```bash
sudo /usr/local/bin/rafz-ssl-retry
```

</details>

<details>
<summary><b>Wings tidak jalan / Docker error</b></summary>

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/healer.sh)
# coba menu 05 atau 06
systemctl status wings docker --no-pager
```

</details>

<details>
<summary><b>Bot server status installing / 409</b></summary>

Tunggu beberapa menit (npm install). Start manual di panel jika perlu.  
GodMode sudah me-retry otomatis.

</details>

<details>
<summary><b>Lupa password panel</b></summary>

```bash
cat /root/rafzhost-panel-data.txt
# atau
cd /var/www/pterodactyl && php artisan p:user:change-password
```

</details>

<details>
<summary><b>Mau hapus semua dan mulai bersih</b></summary>

GodMode menu **2** (ketik `YES`) atau Healer menu **02**.

</details>

<details>
<summary><b>curl: command not found</b></summary>

```bash
apt-get update && apt-get install -y curl
```

</details>

---

## 🔐 Keamanan

1. Hanya jalankan di **VPS milik sendiri**, sebagai **root**.  
2. Jangan kirim **password, PLTA, PLTC, token bot** ke grup publik.  
3. Saat lapor ke [@rafzbotz](https://t.me/rafzbotz), **sensor** rahasia.  
4. File `/root/rafzhost-panel-data.txt` berisi login — jaga izinnya.  
5. Ganti password & token jika pernah bocor di screenshot.  
6. Proyek ini **tidak** terafiliasi resmi dengan Pterodactyl Project.

---

## 🛣 Progress & roadmap

### ✅ Sudah ada (stabil)

- [x] Install Panel + Wings one-liner  
- [x] Location, Node, Allocation otomatis  
- [x] SSL unified + penanganan rate limit + cron retry  
- [x] Wings native TLS :8080  
- [x] Egg Nusantara v9 + pengamanan export  
- [x] Deploy bot Create Panel + generate settings.js  
- [x] Menu uninstall (4 mode)  
- [x] UI berwarna  
- [x] Mode `NONINTERACTIVE`  
- [x] Healer 01–09 + auto-check  
- [x] README super detail + kontak Telegram  

### 🚧 Dikerjakan / diperhalus

- [ ] Start bot tanpa campur tangan manual di semua kondisi edge  
- [ ] Status progress yang ramah di semua aplikasi SSH HP  
- [ ] Deteksi sisa install lebih akurat  

### 📅 Rencana

- [ ] Multi-node dari satu kali jalan script  
- [ ] Backup/restore panel satu perintah  
- [ ] Alert resource ke Telegram/Discord  
- [ ] Rilis ber-tag + mirror  

---

## 📜 Changelog

### GodMode v3.9

- Menu uninstall: Reset VPS, Panel, Wings, Both  
- UI warna (pola Healer), tanpa mengandalkan TTY  
- Perbaikan spam “loading” di terminal  
- Retry start bot saat status still installing  
- Input dipangkas (domain, admin, alias, bot)  
- Alias allocation custom; IP & port otomatis  
- ENV non-interactive lengkap  

### GodMode v3.6 – v3.8

- SSL unified + cron `rafz-ssl-retry`  
- Patch `.env` & nginx proxy headers  
- Integrasi deploy bot.zip  

### GodMode v3.3 – v3.5

- Patch mixed content / trusted proxies  
- Force reinstall sisa Wings  
- Verifikasi panel ↔ wings  

### Healer v3.5

- Auto-check overload & nginx abort  
- Deep clean, docker socket, ciduk hama, rate-limit flush  
- UI cyberpunk  

### Awal

- Integrasi pterodactyl-installer upstream  
- Distribusi one-liner GitHub  

---

## 📬 Kontak & dukungan

| Platform | Akun | Kegunaan |
|----------|------|----------|
| Telegram (akun) | [**@rafzbotz**](https://t.me/rafzbotz) | **Lapor error**, tanya teknis, bantuan script |
| Telegram (channel) | [**@rafzch**](https://t.me/rafzch) | Testimoni, produk yang dijual, info |
| Telegram (channel) | [**@rafzhost**](https://t.me/rafzhost) | Jam kerja, partner, pengumuman resmi |
| GitHub Issues | [Panel-Healer Issues](https://github.com/Rafflie-CH/Panel-Healer/issues) | Bug report berbahasa teknis / PR |

**Template lapor error ke @rafzbotz:**

```text
1. Perintah yang dijalankan:
2. OS VPS (Ubuntu …):
3. Screenshot terminal:
4. Output: tail -50 /root/ptero_install.log
5. Domain panel/node (opsional):
(Jangan kirim password & token bot)
```

---

## 🙏 Credits

- **Author / maintainer:** [Rafflie-CH](https://github.com/Rafflie-CH) (RAFZ)  
- **Brand:** RAFZHOST × DEKZYMARKET  
- **Upstream panel installer:** [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer)  
- **Panel software:** [Pterodactyl](https://pterodactyl.io/)  

---

<div align="center">

### ⚡ Salin perintah (terpisah)

**Install panel**

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/godmode.sh)
```

**Heal panel**

```bash
bash <(curl -sL https://raw.githubusercontent.com/Rafflie-CH/Panel-Healer/main/healer.sh)
```

**VPS tunnel**

```bash
bash <(curl -s https://raw.githubusercontent.com/Rafflie-CH/vps-tunelling/main/bash.sh)
```

<br/>

[![@rafzbotz](https://img.shields.io/badge/Lapor_error-@rafzbotz-26A5E4?style=for-the-badge&logo=telegram)](https://t.me/rafzbotz)
[![@rafzch](https://img.shields.io/badge/Channel-@rafzch-26A5E4?style=for-the-badge&logo=telegram)](https://t.me/rafzch)
[![@rafzhost](https://img.shields.io/badge/Info-@rafzhost-26A5E4?style=for-the-badge&logo=telegram)](https://t.me/rafzhost)

**RAFZHOST × DEKZYMARKET** · Made for Indonesian hosting community ⚡

</div>
