#!/bin/bash

# ======================================================
#   ⚡ PANEL HEALER ULTIMATE TOOLKIT BY RAFZ (V3.5) ⚡
#   Premium VPS Troubleshooting & Hama Killer System
#   Protected Engine Module Developed By RafzHost
# ======================================================

# Definisi Global Path Panel Pterodactyl
PTERO_ROOT="/var/www/pterodactyl"

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
#  🧠 AUTO-SYNC DB ENGINE (MEMBUAT TABLE SETTING PROTEKSI)
# ========================================================
init_database_protect() {
    if ! systemctl is-active --quiet mysql && ! systemctl is-active --quiet mariadb; then
        return
    fi
    sudo mysql -u root -e "
    USE panel;
    CREATE TABLE IF NOT EXISTS \`rafz_protect\` (
        \`key\` VARCHAR(50) PRIMARY KEY,
        \`value\` TEXT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    
    INSERT IGNORE INTO \`rafz_protect\` (\`key\`, \`value\`) VALUES 
    ('status', 'ON'),
    ('whitelist_ids', '1'),
    ('custom_message', '🚫 Akses ditolak! Akun Anda tidak memiliki izin Admin Utama. Hubungi Telegram: @rafzbotz');
    " 2>/dev/null
}

# ========================================================
#  🧠 AUTO-CHECKER SYSTEM (DIAGNOSA REAL-TIME)
# ========================================================
jalankan_auto_check() {
    REKOMENDASI=""
    WARNING_COUNT=0
    echo -e "${DARK}[i] Memindai kondisi VPS lu...${NC}"

    KONEKSI_WEB=$(ss -ant | grep -E ':80|:443' | wc -l)
    if [ "$KONEKSI_WEB" -gt 350 ]; then
        REKOMENDASI="${REKOMENDASI}\n ${RED}• [!] Port Web Overload ($KONEKSI_WEB koneksi). Stuck loading? Sikat MENU [09]${NC}"
        ((WARNING_COUNT++))
    fi

    KONEKSI_WINGS=$(ss -ant | grep -E ':8080' | wc -l)
    if [ "$KONEKSI_WINGS" -gt 200 ]; then
        REKOMENDASI="${REKOMENDASI}\n ${RED}• [!] Wings Overload ($KONEKSI_WINGS spam)! Clear di MENU [09] atau [07]${NC}"
        ((WARNING_COUNT++))
    fi

    if [ -f /var/log/nginx/error.log ]; then
        CRASH_NGINX=$(tail -n 30 /var/log/nginx/error.log | grep -E 'aborting|open socket' | tail -n 1)
        if [ ! -z "$CRASH_NGINX" ]; then
            REKOMENDASI="${REKOMENDASI}\n ${RED}• [!] Nginx Socket Aborting! Web panel mati total. Clear MENU [09]${NC}"
            ((WARNING_COUNT++))
        fi
    fi

    if systemctl is-active --quiet wings 2>/dev/null; then :; else
        REKOMENDASI="${REKOMENDASI}\n ${YELLOW}• [!] Wings Offline/Pingsan. Beresin pake MENU [05] atau cek service.${NC}"
        ((WARNING_COUNT++))
    fi

    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 85 ]; then
        REKOMENDASI="${REKOMENDASI}\n ${RED}• [!] Storage Kritis ($DISK_USAGE% Terpakai)! Cari biang kerok di MENU [07]${NC}"
        ((WARNING_COUNT++))
    fi

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

# ========================================================
#  🧠 CORE PROTECT ENGINE INJECTOR (FULL MENTAHAN VERSION)
# ========================================================
jalankan_injeksi_core() {
    if [ ! -d "$PTERO_ROOT" ]; then
        echo -e "${RED}[ERROR] Direktori panel /var/www/pterodactyl tidak ditemukan!${NC}"
        return
    fi

    # ---- 1. INJECT FULL: ServerController.php ----
    FILE_SERVER_CTRL="$PTERO_ROOT/app/Http/Controllers/Admin/Servers/ServerController.php"
    [ ! -f "${FILE_SERVER_CTRL}.bak" ] && cp "$FILE_SERVER_CTRL" "${FILE_SERVER_CTRL}.bak"
    
    cat << 'EOF' > "$FILE_SERVER_CTRL"
<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Location;
use Pterodactyl\Models\Node;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Allocation;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Servers\ServerCreationService;
use Pterodactyl\Repositories\Eloquent\ServerRepository;
use Pterodactyl\Repositories\Eloquent\DatabaseRepository;
use Pterodactyl\Http\Requests\Admin\ServerFormRequest;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use JavaScript;

class ServerController extends Controller
{
    protected $repository;
    protected $creationService;
    protected $databaseRepository;

    public function __construct(
        ServerRepository $repository,
        ServerCreationService $creationService,
        DatabaseRepository $databaseRepository
    ) {
        $this->repository = $repository;
        $this->creationService = $creationService;
        $this->databaseRepository = $databaseRepository;
    }

    public function index(Request $request)
    {
        $user = Auth::user();
        $protectStatus = DB::table('rafz_protect')->where('key', 'status')->value('value') ?? 'ON';
        $whitelistRaw = DB::table('rafz_protect')->where('key', 'whitelist_ids')->value('value') ?? '1';
        $whitelistIds = explode(',', str_replace(' ', '', $whitelistRaw));

        $query = Server::query()->with('node', 'user', 'allocation');

        if ($request->has('search')) {
            $search = $request->input('search');
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                  ->orWhere('uuid', 'like', "%{$search}%")
                  ->orWhere('external_id', 'like', "%{$search}%");
            });
        }

        if ($protectStatus === 'ON' && !in_array((string)$user->id, $whitelistIds)) {
            $query->where('owner_id', $user->id);
        }

        $servers = $query->paginate(25);
        return view('admin.servers.index', ['servers' => $servers]);
    }

    public function create()
    {
        $nodes = Node::all();
        if (count($nodes) < 1) {
            return redirect()->route('admin.nodes.new')->with('flash_error', 'Anda harus membuat node terlebih dahulu sebelum bisa membuat server.');
        }
        JavaScript::put([
            'nests' => DB::table('nests')->get(),
            'eggs' => DB::table('eggs')->get(),
        ]);
        return view('admin.servers.new', ['nodes' => $nodes]);
    }
}
EOF
    echo -e "${GREEN}[✔] SUCCESS: ServerController.php Full Injected!${NC}"

    # ---- 2. INJECT FULL: DetailsModificationService.php ----
    FILE_DETAIL_SVC="$PTERO_ROOT/app/Services/Servers/DetailsModificationService.php"
    [ ! -f "${FILE_DETAIL_SVC}.bak" ] && cp "$FILE_DETAIL_SVC" "${FILE_DETAIL_SVC}.bak"
    
    cat << 'EOF' > "$FILE_DETAIL_SVC"
<?php

namespace Pterodactyl\Services\Servers;

use Pterodactyl\Models\Server;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

class DetailsModificationService
{
    protected $repository;

    public function __construct(ServerRepositoryInterface $repository)
    {
        $this->repository = $repository;
    }

    public function handle(Server $server, array $data)
    {
        $user = Auth::user();
        $protectStatus = DB::table('rafz_protect')->where('key', 'status')->value('value') ?? 'ON';
        $whitelistRaw = DB::table('rafz_protect')->where('key', 'whitelist_ids')->value('value') ?? '1';
        $customMessage = DB::table('rafz_protect')->where('key', 'custom_message')->value('value') ?? '🚫 Akses ditolak! Hubungi @rafzbotz';
        $whitelistIds = explode(',', str_replace(' ', '', $whitelistRaw));

        if ($protectStatus === 'ON' && !in_array((string)$user->id, $whitelistIds)) {
            if ($server->owner_id !== $user->id) {
                abort(403, $customMessage . " [Engine Security by RafzHost]");
            }
        }

        DB::transaction(function () use ($server, $data) {
            $this->repository->update($server->id, [
                'external_id' => array_get($data, 'external_id'),
                'name' => array_get($data, 'name'),
                'owner_id' => array_get($data, 'owner_id'),
                'description' => array_get($data, 'description'),
            ], true, true);
        });

        return $server;
    }
}
EOF
    echo -e "${GREEN}[✔] SUCCESS: DetailsModificationService.php Full Injected!${NC}"

    # ---- 3. INJECT FULL: StartupModificationService.php ----
    FILE_STARTUP_SVC="$PTERO_ROOT/app/Services/Servers/StartupModificationService.php"
    [ ! -f "${FILE_STARTUP_SVC}.bak" ] && cp "$FILE_STARTUP_SVC" "${FILE_STARTUP_SVC}.bak"
    
    cat << 'EOF' > "$FILE_STARTUP_SVC"
<?php

namespace Pterodactyl\Services\Servers;

use Pterodactyl\Models\Server;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

class StartupModificationService
{
    protected $repository;

    public function __construct(ServerRepositoryInterface $repository)
    {
        $this->repository = $repository;
    }

    public function handle(Server $server, array $data)
    {
        $user = Auth::user();
        $protectStatus = DB::table('rafz_protect')->where('key', 'status')->value('value') ?? 'ON';
        $whitelistRaw = DB::table('rafz_protect')->where('key', 'whitelist_ids')->value('value') ?? '1';
        $customMessage = DB::table('rafz_protect')->where('key', 'custom_message')->value('value') ?? '🚫 Akses ditolak! Hubungi @rafzbotz';
        $whitelistIds = explode(',', str_replace(' ', '', $whitelistRaw));

        if ($protectStatus === 'ON' && !in_array((string)$user->id, $whitelistIds)) {
            if ($server->owner_id !== $user->id) {
                abort(403, $customMessage . " [Engine Security by RafzHost]");
            }
        }

        DB::transaction(function () use ($server, $data) {
            $this->repository->update($server->id, [
                'startup' => array_get($data, 'startup'),
                'custom_image' => array_get($data, 'custom_image'),
            ], true, true);
        });

        return $server;
    }
}
EOF
    echo -e "${GREEN}[✔] SUCCESS: StartupModificationService.php Full Injected!${NC}"

    # ---- 4. INJECT FULL: BuildModificationService.php ----
    FILE_BUILD_SVC="$PTERO_ROOT/app/Services/Servers/BuildModificationService.php"
    [ ! -f "${FILE_BUILD_SVC}.bak" ] && cp "$FILE_BUILD_SVC" "${FILE_BUILD_SVC}.bak"
    
    cat << 'EOF' > "$FILE_BUILD_SVC"
<?php

namespace Pterodactyl\Services\Servers;

use Pterodactyl\Models\Server;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

class BuildModificationService
{
    protected $repository;

    public function __construct(ServerRepositoryInterface $repository)
    {
        $this->repository = $repository;
    }

    public function handle(Server $server, array $data)
    {
        $user = Auth::user();
        $protectStatus = DB::table('rafz_protect')->where('key', 'status')->value('value') ?? 'ON';
        $whitelistRaw = DB::table('rafz_protect')->where('key', 'whitelist_ids')->value('value') ?? '1';
        $customMessage = DB::table('rafz_protect')->where('key', 'custom_message')->value('value') ?? '🚫 Akses ditolak! Hubungi @rafzbotz';
        $whitelistIds = explode(',', str_replace(' ', '', $whitelistRaw));

        if ($protectStatus === 'ON' && !in_array((string)$user->id, $whitelistIds)) {
            if ($server->owner_id !== $user->id) {
                abort(403, $customMessage . " [Engine Security by RafzHost]");
            }
        }

        DB::transaction(function () use ($server, $data) {
            $this->repository->update($server->id, [
                'memory' => array_get($data, 'memory'),
                'swap' => array_get($data, 'swap'),
                'io' => array_get($data, 'io'),
                'cpu' => array_get($data, 'cpu'),
                'disk' => array_get($data, 'disk'),
            ], true, true);
        });

        return $server;
    }
}
EOF
    echo -e "${GREEN}[✔] SUCCESS: BuildModificationService.php Full Injected!${NC}"

    # ---- 5. INJECT FULL: new.blade.php (Lock Owner Create Server) ----
    FILE_NEW_BLADE="$PTERO_ROOT/resources/views/admin/servers/new.blade.php"
    [ ! -f "${FILE_NEW_BLADE}.bak" ] && cp "$FILE_NEW_BLADE" "${FILE_NEW_BLADE}.bak"
    
    cat << 'EOF' > "$FILE_NEW_BLADE"
@extends('layouts.admin')

@section('title', 'New Server')

@section('content-header')
    <h1>Create Server <small>Add a new server to the daemon node.</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li><a href="{{ route('admin.servers') }}">Servers</a></li>
        <li class="active">Create</li>
    </ol>
@endsection

@section('content')
@php
    $protectStatus = \DB::table('rafz_protect')->where('key', 'status')->value('value') ?? 'ON';
    $whitelistRaw = \DB::table('rafz_protect')->where('key', 'whitelist_ids')->value('value') ?? '1';
    $whitelistIds = explode(',', str_replace(' ', '', $whitelistRaw));
    $isWhitelisted = in_array((string)Auth::user()->id, $whitelistIds);
@endphp
<div class="row">
    <form action="{{ route('admin.servers.new') }}" method="POST">
        <div class="col-md-6">
            <div class="box box-primary">
                <div class="box-header with-border">
                    <h3 class="box-title">Core Details</h3>
                </div>
                <div class="box-body">
                    <div class="form-group">
                        <label for="pName" class="control-label">Server Name</label>
                        <input type="text" id="pName" name="name" value="{{ old('name') }}" class="form-control" placeholder="Nama Server">
                    </div>
                    <div class="form-group">
                        <label for="pOwnerId" class="control-label">Server Owner</label>
                        @if($protectStatus === 'ON' && !$isWhitelisted)
                            <input type="hidden" name="owner_id" value="{{ Auth::user()->id }}">
                            <input type="text" class="form-control" value="{{ Auth::user()->username }} ({{ Auth::user()->email }})" readonly disabled>
                            <small class="text-danger">* Izin pembuatan owner eksternal dikunci oleh RafzHost Engine.</small>
                        @else
                            <select id="pOwnerId" name="owner_id" class="form-control" style="width:100%;"></select>
                        @endif
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-6">
            <div class="box box-success">
                <div class="box-header with-border">
                    <h3 class="box-title">Allocation Management</h3>
                </div>
                <div class="box-body">
                    <div class="form-group">
                        <label for="pNodeId" class="control-label">Node</label>
                        <select id="pNodeId" name="node_id" class="form-control">
                            @foreach($nodes as $node)
                                <option value="{{ $node->id }}">{{ $node->name }}</option>
                            @endforeach
                        </select>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-12" style="margin-top:20px;">
            {!! csrf_field() !!}
            <button type="submit" class="btn btn-success pull-right">Create Server</button>
        </div>
    </form>
</div>
@endsection
EOF
    echo -e "${GREEN}[✔] SUCCESS: new.blade.php Full Injected!${NC}"

    # ---- 6. INJECT FULL: admin.blade.php (Sidebar Mod & All-Theme Menu Placement) ----
    FILE_ADMIN_LAYOUT="$PTERO_ROOT/resources/views/layouts/admin.blade.php"
    [ ! -f "${FILE_ADMIN_LAYOUT}.bak" ] && cp "$FILE_ADMIN_LAYOUT" "${FILE_ADMIN_LAYOUT}.bak"

    sed -i '/<aside class="main-sidebar">/a \ \ \ \ @php\n        $pStatus = \\DB::table('\''rafz_protect'\'')->where('\''key'\'', '\''status'\'')->value('\''value'\'') ?? '\''ON'\'';\n        $pWL = \\DB::table('\''rafz_protect'\'')->where('\''key'\'', '\''whitelist_ids'\'')->value('\''value'\'') ?? '\''1'\'';\n        $pWL_ids = explode('\'','\'', str_replace('\'' '\''', '\'\'', $pWL));\n        $isRafzAdmin = in_array((string)Auth::user()->id, $pWL_ids);\n    @endphp' "$FILE_ADMIN_LAYOUT"

    sed -i '/<span>Application API<\/span>/,/<\/a>/ {
        /<\/a>/a \ \ \ \ \ \ \ \ \ \ \ \ <li class="{{ $pStatus === "ON" ? "text-warning" : "" }}">\n                <a href="/admin/rafz-protection">\n                    <i class="fa fa-shield text-aqua"></i> <span>Protect Engine</span>\n                </a>\n            </li>
    }' "$FILE_ADMIN_LAYOUT"
    echo -e "${GREEN}[✔] SUCCESS: layouts/admin.blade.php Sidebar Universal Injected!${NC}"

    # ---- 7. INJECT ROUTE & DASHBOARD WEB MANAGEMENT ----
    FILE_ROUTE_ADMIN="$PTERO_ROOT/routes/admin.php"
    if [ -f "$FILE_ROUTE_ADMIN" ] && ! grep -q "rafz-protection" "$FILE_ROUTE_ADMIN"; then
        cat << 'EOF' >> "$FILE_ROUTE_ADMIN"

// ====================================================================
// ⚡ CORE ROUTE INTERACTIVE PROTECT ENGINE DEVELOPED BY RAFZHOST ⚡
// ====================================================================
Route::get('/rafz-protection', function () {
    if (!in_array((string)Auth::user()->id, explode(',', str_replace(' ', '', \DB::table('rafz_protect')->where('key', 'whitelist_ids')->value('value') ?? '1')))) {
        abort(403, 'Akses Terlarang! Hanya Whitelist ID Utama yang dapat mengonfigurasi modul.');
    }
    
    if (request()->has('save_rafz_engine')) {
        \DB::table('rafz_protect')->where('key', 'status')->update(['value' => request('status')]);
        \DB::table('rafz_protect')->where('key', 'whitelist_ids')->update(['value' => request('whitelist_ids')]);
        \DB::table('rafz_protect')->where('key', 'custom_message')->update(['value' => request('custom_message')]);
        return redirect('/admin/rafz-protection')->with('flash_success', 'Konfigurasi Engine RafzHost Berhasil Diperbarui!');
    }

    $status = \DB::table('rafz_protect')->where('key', 'status')->value('value') ?? 'ON';
    $whitelist = \DB::table('rafz_protect')->where('key', 'whitelist_ids')->value('value') ?? '1';
    $message = \DB::table('rafz_protect')->where('key', 'custom_message')->value('value') ?? '🚫 Akses ditolak! Hubungi @rafzbotz';

    echo "
    <link rel='stylesheet' href='https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.4.1/css/bootstrap.min.css'>
    <body style='background:#ecf0f5; padding:20px; font-family:sans-serif;'>
        <div class='container-fluid'>
            <div class='box box-solid' style='border-radius:6px; box-shadow:0 2px 10px rgba(0,0,0,0.1); background:#fff; overflow:hidden;'>
                <div class='box-header' style='background:linear-gradient(45deg, #1e3c72, #2a5298); color:#fff; padding:15px;'>
                    <h3 class='box-title' style='margin:0; font-weight:bold;'>⚙️ Rafz Protection Engine Dashboard v1.5</h3>
                    <p style='margin:5px 0 0 0; font-size:12px; opacity:0.8;'>Manage core limits, whitelist user id array, and alerts control globally.</p>
                </div>
                <form method='GET' action='' class='box-body' style='padding:25px;'>
                    <input type='hidden' name='save_rafz_engine' value='1'>
                    <div class='form-group'>
                        <label style='font-weight:bold;'>SWITCH MASTER ENGINE PROTECTION</label>
                        <select name='status' class='form-control' style='height:40px;'>
                            <option value='ON' ".($status=='ON'?'selected':'').">🟢 SYSTEM ENGINE ACTIVE (ON)</option>
                            <option value='OFF' ".($status=='OFF'?'selected':'').">🔴 SYSTEM ENGINE BYPASS (OFF)</option>
                        </select>
                    </div>
                    <br>
                    <div class='form-group'>
                        <label style='font-weight:bold;'>WHITELIST ID ADMIN SELLER (Gunakan Koma [,] Jika Banyak)</label>
                        <input type='text' name='whitelist_ids' class='form-control' value='\".e(\$whitelist).\"' style='height:40px;' placeholder='Contoh: 1,5,10'>
                        <small class='text-muted'>* ID yang terdaftar di atas kebal dari sistem pemblokiran & pembatasan sub-admin. Anda bisa menambahkannya langsung dari sini!</small>
                    </div>
                    <br>
                    <div class='form-group'>
                        <label style='font-weight:bold;'>CUSTOM ALERT PENOLAKAN AKSES (SUB-ADMIN)</label>
                        <textarea name='custom_message' class='form-control' style='height:100px; resize:vertical;'>\".e(\$message).\"</textarea>
                    </div>
                    <br>
                    <button type='submit' class='btn btn-primary btn-block' style='height:45px; font-weight:bold; font-size:15px; background:#2a5298; border:none;'>SIMPAN PERUBAHAN CONFIG</button>
                    <hr>
                    <p class='text-center text-muted' style='font-size:11px;'>Core Module Protected Written By Rafz Dev — Telegram Support: <a href='https://t.me/rafzbotz' target='_blank'>@rafzbotz</a></p>
                </form>
            </div>
        </div>
    </body>";
    exit;
});
EOF
    fi

    echo -e "${BLUE}[+] Menghapus cache temporary view Laravel panel...${NC}"
    cd "$PTERO_ROOT" && php artisan view:clear && php artisan cache:clear 2>/dev/null
    echo -e "${GREEN}[✔] SUCCESS TOTAL: Seluruh Engine Proteksi Rafz Berhasil Aktif!🚀${NC}"
}

# ========================================================
#  ⚡ LOOP UTAMA RUNNING LOOP TOOLKIT HEALER UTUH
# ========================================================
while true; do
clear
echo -e "${PURPLE}⚡ SYSTEM CORE PANEL HEALER BY RAFZ (V3.5) ⚡${NC}"
echo -e "${DARK}Ultimate VPS Automation & Troubleshooting${NC}"
echo -e "${CYAN}─────────────────────────────────────────────${NC}"
echo -e " ${WHITE}Welcome back, Rafz! Hasil Cek Sistem:${NC}"
echo -e ""

# Jalankan diagnosa di dashboard utama & init DB
init_database_protect
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
echo -e " ${YELLOW}[10]${NC} ⚙️  PROTECT ENGINE CORE  ${DARK}-> Kontrol Pembatasan Sub-Admin (RafzHost)${NC}"
echo -e " ${RED}[X]${NC}  ❌ SHUTDOWN TERMINAL   ${DARK}-> Keluar dari Script${NC}"
echo -e "${CYAN}─────────────────────────────────────────────${NC}"

while true; do
    echo -ne "${CYAN}[✦] Rafz@Toolkit:~# ${NC}"
    read -r pilihan
    if [[ -z "$pilihan" ]]; then
        echo -e "${RED}[!] Opsi kosong bro, ketik nomor menunya!${NC}"
    elif [[ "$pilihan" =~ ^[Xx]$ ]] || [ "$pilihan" = "0" ]; then
        echo -e "\n${GREEN}[✔] Keluar dari script. Written by Rafz Dev. See you!${NC}\n"
        exit 0
    elif [[ "$pilihan" =~ ^[1-9]$ ]] || [[ "$pilihan" =~ ^[0-1][0-9]$ ]]; then
        pilihan=$(echo "$pilihan" | sed 's/^0//')
        break
    else
        echo -e "${RED}[!] Pilihan gak ada bro! Input nomor [1-10] atau [X].${NC}"
    fi
done

case $pilihan in
    1)
        clear
        echo -e "${CYAN}🔒 FIX DPKG LOCK${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        echo -e "${RED}❌ E: Could not get lock /var/lib/dpkg/lock-frontend...${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        while true; do
            echo -ne "${YELLOW}[?] Gas lepas gembok database APT? (y/n/x): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock
                dpkg --configure -a && apt-get clean && apt-get update
                echo -e "${GREEN}[✔] SUCCESS: Database DPKG berhasil dibuka kembali!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then break
            else echo -e "${RED}[!] Ketik y, n, atau x bro.${NC}"
            fi
        done
        ;;
        
    2)
        clear
        echo -e "${CYAN}☢️  DEEP CLEAN WIPE OUT${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        while true; do
            echo -ne "${RED}[💀] Lu yakin mau WIPE OUT TOTAL isi VPS ini? (y/n/x): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                sudo systemctl stop wings pteroq nginx mysql mariadb redis-server 2>/dev/null
                sudo killall -9 nginx mariadb mysqld redis-server 2>/dev/null
                sudo docker stop $(sudo docker ps -a -q) 2>/dev/null
                sudo docker rm $(sudo docker ps -a -q) 2>/dev/null
                sudo apt-get purge -y docker-ce docker-ce-cli nginx* mysql-* mariadb-* php* 2>/dev/null
                sudo rm -rf /var/lib/docker /var/www/pterodactyl /etc/pterodactyl /var/lib/mysql
                sudo apt-get autoremove -y && sudo apt-get clean
                echo -e "${GREEN}[✔] SUCCESS TOTAL: OS VPS bersih total kek baru install!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then break
            fi
        done
        ;;

    3)
        clear
        echo -e "${CYAN}🧹 DISK QUICK CLEAN DISK${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        while true; do
            echo -ne "${YELLOW}[?] Jalankan pembersihan cache sampah? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                sudo apt-get clean
                sudo rm -rf /var/log/journal/* 2>/dev/null
                sudo find /var/log -type f -regex '.*\.gz$\|.*\.1$' -delete
                sudo find /var/log -type f -exec truncate -s 0 {} +
                sudo rm -rf /tmp/*
                echo -e "${GREEN}[✔] SUCCESS: Ruang penyimpanan berhasil dilegakan!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then break
            fi
        done
        ;;

    4)
        clear
        echo -e "${CYAN}🧨 MANUAL WIPE DATA SERVER${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        while true; do
            echo -ne "${RED}[💀] Lu yakin mau wipe data game & database SQL? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                sudo systemctl stop wings pteroq 2>/dev/null
                sudo rm -rf /var/lib/pterodactyl /etc/pterodactyl /var/www/pterodactyl /var/log/pterodactyl
                sudo apt-get purge -y mariadb-server mysql-server 2>/dev/null
                echo -e "${GREEN}[✔] SUCCESS: Semua folder server game raksasa lenyap!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then break
            fi
        done
        ;;

    5)
        clear
        echo -e "${CYAN}🔌 FIX DOCKER SOCKET${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        while true; do
            echo -ne "${YELLOW}[?] Reset jalur komunikasi Docker Socket? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                sudo systemctl stop docker.socket && sudo systemctl stop docker
                sudo rm -f /var/run/docker.sock
                sudo systemctl start docker.socket && sudo systemctl start docker
                echo -e "${GREEN}[✔] SUCCESS: Docker Socket normal kembali!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then break
            fi
        done
        ;;

    6)
        clear
        echo -e "${CYAN}🌀 FORCE REBUILD DOCKER${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        while true; do
            echo -ne "${YELLOW}[?] Paksa install ulang komponen utama Docker? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                sudo apt-get install --reinstall docker-ce docker-ce-cli containerd.io -y
                sudo systemctl daemon-reload && sudo systemctl enable --now docker
                echo -e "${GREEN}[✔] SUCCESS: Engine Docker berhasil di-rebuild!${NC}"
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then break
            fi
        done
        ;;

    7)
        clear
        echo -e "${CYAN}🚨 LAPORAN PEMAKAIAN DISK${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        df -h / | awk 'NR==2 {print " • Total Size : " $2 "\n • Terpakai   : " $3 "\n • Tersedia   : " $4}'
        TARGET_PATH=$(du -sh /var/lib/pterodactyl/volumes/* 2>/dev/null | sort -hr | head -n 1)
        if [ -z "$TARGET_PATH" ]; then
            echo -e "${RED} • [!] Folder data server kosong.${NC}"
            tunggu_enter ; continue
        fi
        SIZE=$(echo "$TARGET_PATH" | awk '{print $1}')
        FOLDER=$(echo "$TARGET_PATH" | awk '{print $2}')
        UUID=$(basename "$FOLDER")
        SHORT_UUID=${UUID:0:8}
        echo -e " • Size Terbesar : ${RED}$SIZE${NC}\n • Lokasi Folder : ${DARK}$FOLDER${NC}"
        DB_CHECK=$(sudo mysql -u root -e "USE panel; SELECT s.id FROM servers s WHERE s.uuid LIKE '$SHORT_UUID%';" 2>/dev/null)
        if [ -z "$DB_CHECK" ]; then
            while true; do
                echo -ne "${YELLOW}[?] Folder sisa hantu ketemu. Hapus paksa foldernya? (y/n): ${NC}"
                read -r hapus_yatim
                if [[ "$hapus_yatim" =~ ^[Yy]$ ]]; then sudo rm -rf "$FOLDER"; echo -e "${GREEN}[✔] Sukses bersihin!${NC}"; break; fi
            done
            tunggu_enter ; continue
        fi
        sudo mysql -u root -e "USE panel; SELECT s.id AS 'ID', s.name AS 'Nama', u.username AS 'User', u.email AS 'Email' FROM servers s JOIN users u ON s.owner_id = u.id WHERE s.uuid LIKE '$SHORT_UUID%';"
        echo -ne "${WHITE}[?] Lu yakin mau delete server berukuran ${RED}$SIZE${WHITE} ini? (y/n): ${NC}"
        read -r PILIHAN
        if [[ "$PILIHAN" =~ ^[Yy]$ ]]; then
            sudo docker kill "$UUID" 2>/dev/null; sudo docker rm "$UUID" 2>/dev/null; sudo rm -rf "$FOLDER"
            sudo mysql -u root -e "USE panel; DELETE FROM servers WHERE uuid LIKE '$SHORT_UUID%';" 2>/dev/null
            sudo systemctl restart wings
            echo -e "${GREEN}[✔] BERES! Node adem lagi.🚀${NC}"
        fi
        tunggu_enter
        ;;

    8)
        clear
        echo -e "${CYAN}📥 PTERODACTYL OFFICIAL INSTALLER${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        while true; do
            echo -ne "${YELLOW}[?] Download & jalankan script installer? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                if ! command -v curl &> /dev/null; then apt-get update && apt-get install -y curl; fi
                bash <(curl -s https://pterodactyl-installer.se)
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then break
            fi
        done
        ;;

    9)
        clear
        echo -e "${CYAN}🛡️  ANTI-DDOS & FLUSH PORT SYSTEM${NC}"
        echo -e "${CYAN}─────────────────────────────────────────────${NC}"
        while true; do
            echo -ne "${YELLOW}[?] Pasang pembatas request & bersihkan antrean port? (y/n): ${NC}"
            read -r konfirmasi
            if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                CONF_PATH="/etc/nginx/sites-available/pterodactyl.conf"
                if [ -f "$CONF_PATH" ] && ! grep -q "zone=panel_limit" "$CONF_PATH"; then
                    sed -i '1i limit_req_zone $binary_remote_addr zone=panel_limit:10m rate=10r/s;' "$CONF_PATH"
                    sed -i '/location ~ \\.php\$/a \ \ \ \ limit_req zone=panel_limit burst=20 nodelay;' "$CONF_PATH"
                fi
                ulimit -n 65535; ss -K dst :80 2>/dev/null; ss -K dst :443 2>/dev/null; ss -K dst :8080 2>/dev/null
                if nginx -t; then
                    systemctl restart nginx php8.1-fpm php8.2-fpm php8.3-fpm wings 2>/dev/null
                    echo -e "${GREEN}[✔] SUCCESS: Jaringan & Node dilegakan!🚀${NC}"
                fi
                tunggu_enter ; break
            elif [[ "$konfirmasi" =~ ^[Nn]$ ]] || [[ "$konfirmasi" =~ ^[Xx]$ ]]; then break
            fi
        done
        ;;

    10)
        clear
        while true; do
            STATUS_PROTECT=$(sudo mysql -u root -e "USE panel; SELECT \`value\` FROM \`rafz_protect\` WHERE \`key\`='status';" -sN 2>/dev/null)
            WHITELIST_IDS=$(sudo mysql -u root -e "USE panel; SELECT \`value\` FROM \`rafz_protect\` WHERE \`key\`='whitelist_ids';" -sN 2>/dev/null)
            ALERT_MSG=$(sudo mysql -u root -e "USE panel; SELECT \`value\` FROM \`rafz_protect\` WHERE \`key\`='custom_message';" -sN 2>/dev/null)
            [ -z "$STATUS_PROTECT" ] && STATUS_PROTECT="OFF (BELUM DI-INJECT)"
            [ -z "$WHITELIST_IDS" ] && WHITELIST_IDS="1"
            [ -z "$ALERT_MSG" ] && ALERT_MSG="🚫 Akses ditolak! Hubungi Telegram: @rafzbotz"

            clear
            echo -e "${YELLOW}⚙️  PROTECT ENGINE CORE MANAGEMENT — BY RAFZHOST${NC}"
            echo -e "${CYAN}─────────────────────────────────────────────${NC}"
            echo -e " ${WHITE}Status Proteksi Panel :${NC} $([ "$STATUS_PROTECT" = "ON" ] && echo -e "${GREEN}ACTIVE (ON)${NC}" || echo -e "${RED}INACTIVE (OFF)${NC}")"
            echo -e " ${WHITE}Whitelist ID Admin    :${NC} ${YELLOW}$WHITELIST_IDS${NC}"
            echo -e " ${WHITE}Teks Notifikasi Alert :${NC} ${CYAN}$ALERT_MSG${NC}"
            echo -e "${CYAN}─────────────────────────────────────────────${NC}"
            echo -e " ${PURPLE}[1]${NC} 🔥 SWITCH ENGINE (ON / OFF)"
            echo -e " ${PURPLE}[2]${NC} 🔑 UBAH / TAMBAH WHITELIST ID ADMIN"
            echo -e " ${PURPLE}[3]${NC} 💬 CUSTOM TEKS NOTIFIKASI ALERT"
            echo -e " ${GREEN}[4]${NC} 📥 INJECT PROTEKSI ALL FILE PANEL"
            echo -e " ${RED}[5]${NC} 🗑️  UNINSTALL TOTAL SEMUA PROTEKSI"
            echo -e " ${RED}[X]${NC} ↩️  KEMBALI KE MENU UTAMA HEALER"
            echo -e "${CYAN}─────────────────────────────────────────────${NC}"
            echo -ne "${YELLOW}[✦] Rafz@ProtectEngine:~# ${NC}"
            read -r sub_pilihan

            if [[ "$sub_pilihan" =~ ^[Xx]$ ]] || [ "$sub_pilihan" = "0" ]; then break; fi

            case $sub_pilihan in
                1)
                    if [ "$STATUS_PROTECT" = "ON" ]; then
                        sudo mysql -u root -e "USE panel; UPDATE \`rafz_protect\` SET \`value\`='OFF' WHERE \`key\`='status';" 2>/dev/null
                    else
                        sudo mysql -u root -e "USE panel; UPDATE \`rafz_protect\` SET \`value\`='ON' WHERE \`key\`='status';" 2>/dev/null
                    fi
                    ;;
                2)
                    echo -ne "\n${YELLOW}[✦] Masukkan ID Whitelist Baru (misal: 1,2,5): ${NC}"
                    read -r input_id
                    [ ! -z "$input_id" ] && sudo mysql -u root -e "USE panel; UPDATE \`rafz_protect\` SET \`value\`='$input_id' WHERE \`key\`='whitelist_ids';" 2>/dev/null
                    ;;
                3)
                    echo -ne "\n${YELLOW}[✦] Teks Alert Custom: ${NC}"
                    read -r input_msg
                    [ ! -z "$input_msg" ] && sudo mysql -u root -e "USE panel; UPDATE \`rafz_protect\` SET \`value\`='$input_msg' WHERE \`key\`='custom_message';" 2>/dev/null
                    ;;
                4)
                    clear; jalankan_injeksi_core; tunggu_enter ;;
                5)
                    clear
                    echo -e "${BLUE}[+] Mengembalikan file cadangan original (.bak)...${NC}"
                    [ -f "$PTERO_ROOT/app/Http/Controllers/Admin/Servers/ServerController.php.bak" ] && mv "$PTERO_ROOT/app/Http/Controllers/Admin/Servers/ServerController.php.bak" "$PTERO_ROOT/app/Http/Controllers/Admin/Servers/ServerController.php"
                    [ -f "$PTERO_ROOT/resources/views/admin/servers/new.blade.php.bak" ] && mv "$PTERO_ROOT/resources/views/admin/servers/new.blade.php.bak" "$PTERO_ROOT/resources/views/admin/servers/new.blade.php"
                    [ -f "$PTERO_ROOT/app/Services/Servers/DetailsModificationService.php.bak" ] && mv "$PTERO_ROOT/app/Services/Servers/DetailsModificationService.php.bak" "$PTERO_ROOT/app/Services/Servers/DetailsModificationService.php"
                    [ -f "$PTERO_ROOT/app/Services/Servers/StartupModificationService.php.bak" ] && mv "$PTERO_ROOT/app/Services/Servers/StartupModificationService.php.bak" "$PTERO_ROOT/app/Services/Servers/StartupModificationService.php"
                    [ -f "$PTERO_ROOT/app/Services/Servers/BuildModificationService.php.bak" ] && mv "$PTERO_ROOT/app/Services/Servers/BuildModificationService.php.bak" "$PTERO_ROOT/app/Services/Servers/BuildModificationService.php"
                    [ -f "$PTERO_ROOT/resources/views/layouts/admin.blade.php.bak" ] && mv "$PTERO_ROOT/resources/views/layouts/admin.blade.php.bak" "$PTERO_ROOT/resources/views/layouts/admin.blade.php"
                    sudo mysql -u root -e "USE panel; DROP TABLE IF EXISTS \`rafz_protect\`;" 2>/dev/null
                    cd "$PTERO_ROOT" && php artisan view:clear && php artisan cache:clear 2>/dev/null
                    echo -e "${GREEN}[✔] Sukses diuninstall bersih!${NC}"; tunggu_enter ;;
            esac
        done
        ;;
esac
done
