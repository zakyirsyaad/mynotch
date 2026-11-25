# Agent Monitor — Desain

Tanggal: 2026-11-25
Branch: `mynotch` (fork pribadi boring.notch, tidak untuk upstream)
Status: draf, menunggu review

## 1. Tujuan

Notch menunjukkan agent AI yang sedang berjalan di laptop, supaya pengguna tahu
kapan sebuah agent butuh perhatian tanpa harus berpindah jendela.

Kriteria berhasil:

- Saat sesi Claude Code atau Codex meminta izin, notch tertutup menampilkan
  notifikasi "butuh izin" dalam 2 detik.
- Setelah izin dijawab, status agent kembali ke "berjalan".
- Tab agent di notch terbuka mendaftar semua agent yang berjalan, termasuk agent
  tanpa hooks yang terdeteksi dari daftar proses.
- Agent yang ada di daftar bawaan dan baru di-install nanti terdeteksi tanpa
  mengubah kode.

## 2. Ruang lingkup

Termasuk:

- Notifikasi sementara di notch tertutup (dengan atau tanpa musik).
- Tab "Agents" di notch terbuka.
- Deteksi hybrid: laporan lewat hooks + pemindaian proses.
- Daftar agent bawaan (data) dan penambahan agent dari proses yang berjalan.
- Logo agent.
- Seksi Settings "Agents".
- Build pribadi: bundle ID sendiri, Sparkle dimatikan.

Tidak termasuk (siklus berikutnya):

- Integrasi Discord: status voice, status agent ke bot, Rich Presence. Integrasi
  itu akan memakai `AgentMonitorKit` dari desain ini sebagai sumber data.
- Indikator permanen di notch tertutup (sengaja ditolak).
- Mengontrol agent dari notch (menghentikan, menyetujui izin).
- Membuka sesi tertentu di dalam app Claude Desktop; yang dibuka hanya app-nya.

## 3. Pengalaman pengguna

### 3.1 Notifikasi di notch tertutup

- Dipicu oleh perubahan status menjadi `waiting` (butuh input), `error`, atau
  `done` (selesai). Status `running` tidak memicu notifikasi.
- Tampilan: notch melebar (lebar total 540 pt, supaya sayap kiri dan kanan cukup ruang di samping notch fisik ~200 pt). Sayap kiri: logo agent, nama
  agent, dan nama folder proyek. Sayap kanan: titik warna dan label status.
- Durasi: 5 detik untuk `waiting`, 3 detik untuk `error` dan `done`.
- Antrean: notifikasi ditampilkan satu per satu sesuai urutan datang. Event
  beruntun dari sesi yang sama yang belum tampil digabung; yang tampil hanya
  status terakhir.
- Tidak ditampilkan bila:
  - app asal agent sedang menjadi app aktif (frontmost),
  - notch sedang disembunyikan karena media fullscreen (`hideOnClosed`),
  - jenis notifikasi itu dimatikan di Settings,
  - notch sedang terbuka.
- Bila pengguna meng-hover atau mengetuk (tap) notch saat notifikasi agent tampil,
  notifikasi langsung ditutup dan notch terbuka langsung di tab Agents.
- Setelah notifikasi selesai, notch kembali ke tampilan sebelumnya (live
  activity musik atau kosong).

Warna status: `running` teal, `waiting` amber, `error` merah, `done` hijau.

### 3.2 Tab Agents di notch terbuka

- Tab ketiga setelah Home dan Shelf, ikon SF Symbol `sparkles`.
- Satu baris per sesi agent, diurutkan: `waiting`, `error`, `running`, `done`.
  Di dalam status yang sama, yang paling baru berubah di atas.
- Isi baris:
  - logo agent (22 pt),
  - judul: nama tampilan agent + " · " + nama folder `cwd` (bila ada),
  - subjudul: pesan terakhir yang relevan (misalnya teks permintaan izin,
    dipotong 80 karakter), atau "Berjalan", "Selesai", atau
    "Terdeteksi dari proses" untuk agent tanpa hooks,
  - kanan: titik status dan lama berjalan ("4 mnt", "1 jam"),
  - bila ada subagent aktif: label "2 subagent" di subjudul.
- Klik baris: mengaktifkan app asal agent (lihat 5.6).
- Kosong: teks "Tidak ada agent yang berjalan".
- Daftar bisa di-scroll; tinggi area konten mengikuti notch terbuka yang ada.

### 3.3 Settings → Agents

- Saklar utama "Pantau agent".
- Saklar per notifikasi: "Butuh input", "Error", "Selesai".
- Tombol "Pasang hooks" dan "Lepas hooks" untuk Claude Code dan Codex, dengan
  status terpasang/tidak terpasang per agent.
- Daftar agent tambahan buatan pengguna, dengan tombol
  "Tambah dari proses yang berjalan" (memilih dari daftar proses milik pengguna
  yang sedang berjalan) dan tombol hapus.
- Per agent: pilih gambar logo custom.

## 4. Arsitektur

```
Agent (hooks) ──▶ notch-report ──▶ ~/.mynotch/inbox/*.json
                                              │
                                              ▼
                 ProcessScanner ──▶ AgentMonitorManager ◀── InboxWatcher
                                     (memegang AgentState)
                                              │
                         ┌────────────────────┴───────────────┐
                         ▼                                    ▼
                 Notifikasi (expandingView)             Tab Agents
```

Dua lapis:

1. **`AgentMonitorKit`**: paket Swift lokal di `AgentMonitorKit/`. Berisi semua
   logika tanpa UI dan tanpa efek samping sistem: model, parsing event inbox,
   adapter format hooks, reducer status, kebijakan notifikasi, pencocokan
   proses, registry, dan penggabungan JSON untuk pemasangan hooks. Diuji
   dengan `swift test` di paketnya sendiri, tanpa harus mem-build app.
2. **Lapis app** di `boringNotch/managers/AgentMonitor/` dan
   `boringNotch/components/Agents/`: membaca folder, memindai proses,
   menelusuri proses induk, mengambil ikon, dan menggambar UI. Lapis ini tipis
   dan memanggil fungsi-fungsi murni dari `AgentMonitorKit`.

`AgentMonitorManager` adalah singleton `@MainActor ObservableObject`, mengikuti
pola `MusicManager` dan `BatteryActivityManager`.

## 5. Komponen

### 5.1 `notch-report` (skrip shell)

Lokasi terpasang: `~/.mynotch/bin/notch-report`. Sumbernya disimpan di repo
sebagai resource paket
(`AgentMonitorKit/Sources/AgentMonitorKit/Resources/notch-report.sh`), sehingga
test paket dan app memakai file yang sama, dan disalin oleh app saat
"Pasang hooks".

Pemanggilan dari hook: `~/.mynotch/bin/notch-report <source> <event>`.

Perilaku:

1. Validasi `<source>` dan `<event>` cocok dengan `^[A-Za-z0-9_-]{1,64}$`.
   Bila tidak, keluar dengan kode 0 tanpa menulis apa pun.
2. Baca stdin maksimal 262.144 byte (`head -c`). Stdin kosong ditulis sebagai
   `null`.
3. Tulis ke `~/.mynotch/inbox/.tmp-<ts>-<pid>-<rand>`:
   `{"v":1,"source":"<source>","event":"<event>","pid":<PPID>,"ts":<epoch>,"payload":<stdin>}`
4. `mv` ke `~/.mynotch/inbox/<ts>-<pid>-<rand>.json` (atomik di volume yang
   sama).
5. Selalu keluar dengan kode 0 dan tidak menulis ke stdout, supaya tidak
   memengaruhi agent.

Folder dibuat dengan `umask 077` bila belum ada.

### 5.2 Format event dan adapter

`InboxEvent` (di `AgentMonitorKit`) adalah hasil decode amplop di atas.
`payload` disimpan sebagai `JSONValue` mentah.

`ClaudeFormatAdapter` mengubah `InboxEvent` menjadi `AgentEvent`. Adapter ini
dipakai untuk Claude Code, Codex, dan agent lain yang memakai format hooks
Claude (nama event PascalCase, payload berisi `session_id`, `cwd`,
`hook_event_name`). Field yang diambil:

| Field payload | Dipakai untuk |
|---|---|
| `session_id` | identitas sesi; bila tidak ada, pakai `<source>-<pid>` |
| `cwd` | nama folder proyek |
| `message` (Notification) | subjudul saat `waiting`, dipotong 80 karakter |
| `tool_name` (PermissionRequest) | subjudul "Izinkan <tool_name>?" |

Teks prompt (`prompt` pada UserPromptSubmit) dan input/output tool tidak
disimpan.

Pemetaan event ke perubahan status:

| Event | Status baru |
|---|---|
| `SessionStart`, `UserPromptSubmit`, `PostToolUse` | `running` |
| `Notification`, `PermissionRequest` | `waiting` |
| `Stop` | `done` |
| `StopFailure` (bila dikirim oleh versi agent terpasang) | `error` |
| `SubagentStart` / `SubagentStop` | jumlah subagent +1 / −1 (min 0) |
| `SessionEnd` | sesi dihapus |
| event lain | diabaikan |

Status `error` hanya bisa muncul dari agent yang mengirim event kegagalan.
Langkah pertama implementasi adalah merekam payload asli dari Claude Code dan
Codex terpasang untuk memastikan nama event dan field di atas; tabel ini
disesuaikan dengan hasil rekaman sebelum adapter ditulis.

### 5.3 `AgentState` dan reducer

`AgentSession`: `id`, `agentID` (kunci registry), `pid`, `cwdName`, `status`,
`detail` (teks pendek), `subagentCount`, `startedAt`, `updatedAt`,
`origin` (`.hooks` atau `.process`).

`AgentState` adalah struct tak berubah (immutable) berisi `[String: AgentSession]`.
Fungsi murni:

- `reduce(state, AgentEvent, now) -> (AgentState, [StatusChange])`
- `merge(state, scannedProcesses, now) -> AgentState`: menambah sesi `.process`
  untuk proses yang cocok dan belum diwakili sesi `.hooks` dengan PID yang sama;
  menghapus sesi `.process` yang prosesnya sudah tidak ada.
- `prune(state, isAlive: (pid) -> Bool) -> AgentState`: menghapus sesi yang
  PID-nya mati.

### 5.4 `NotificationPolicy`

Fungsi murni `shouldNotify(change, settings, context) -> NoticeDecision`, dengan
`context` berisi: app aktif sekarang, apakah notch terbuka, dan apakah
`hideOnClosed`. Mengembalikan durasi tampil atau "jangan tampil". Antrean dan
penggabungan per sesi juga ada di sini sebagai struct `NoticeQueue`.

### 5.5 `InboxWatcher` dan `ProcessScanner` (lapis app)

`InboxWatcher`:

- `DispatchSource` pada folder `~/.mynotch/inbox` (event `.write`). Saat start
  juga memproses file yang sudah ada.
- Hanya memproses file biasa berakhiran `.json` (bukan symlink, pemilik = user
  saat ini, ukuran ≤ 300 KB). File `.tmp-*` dilewati.
- Event berumur lebih dari 10 menit dibuang tanpa diproses.
- Setiap file dihapus setelah dibaca, berhasil atau gagal. Kegagalan dicatat
  lewat `os.Logger` (subsystem bundle ID, kategori `AgentMonitor`).

`ProcessScanner`:

- Berjalan tiap 5 detik di background queue. Hasilnya dikirim ke main actor.
- Mengambil daftar PID milik user lewat `proc_listallpids`, lalu nama
  executable, PID induk, dan argumen (`sysctl KERN_PROCARGS2`).
- Pencocokan memakai `ProcessMatcher` dari `AgentMonitorKit` dengan aturan
  dari registry dan daftar tambahan pengguna.
- Bila pemindaian gagal, state terakhir dipertahankan.

### 5.6 `HostAppResolver`

Menelusuri PID induk mulai dari PID agent (maksimal 16 langkah) sampai ketemu
PID yang cocok dengan `NSRunningApplication` yang punya `bundleIdentifier`.
Hasil disimpan per sesi. Dipakai untuk:

- menekan notifikasi bila app itu frontmost,
- tindakan klik baris (`activate()`).

Saat menerima event hooks, PID dari `notch-report` bisa berupa shell perantara.
Resolver juga dipakai untuk mencari PID agent yang sebenarnya: telusuri ke atas
sampai menemukan proses yang cocok dengan aturan agent tersebut di registry.
Bila tidak ketemu, pakai PID asli dari event.

### 5.7 Registry agent

File data `AgentMonitorKit/Sources/AgentMonitorKit/Resources/agents.json`.
Setiap entri:

```json
{
  "id": "claude-code",
  "displayName": "Claude Code",
  "match": { "executable": ["claude"], "argvContains": [] },
  "appBundleIDs": ["com.anthropic.claudefordesktop"],
  "hooks": { "format": "claude", "config": "~/.claude/settings.json" }
}
```

Aturan cocok: nama executable sama persis (peka huruf besar-kecil), atau nama
executable adalah interpreter (`node`, `bun`, `python3`, `python`) dan salah
satu argumen basename-nya ada di `argvContains`.

Isi awal:

| id | executable | argvContains | app untuk logo | hooks |
|---|---|---|---|---|
| claude-code | claude | — | com.anthropic.claudefordesktop | claude, `~/.claude/settings.json` |
| codex | codex | — | — | claude, `~/.codex/hooks.json` |
| gemini-cli | gemini | gemini | com.google.GeminiMacOS | — |
| cursor-agent | cursor-agent | — | Cursor (`com.todesktop.230313mzl4w4u92`) | — |
| aider | aider | aider | — | — |
| opencode | opencode | opencode | — | — |
| goose | goose | — | — | — |
| amp | amp | amp | — | — |
| qwen-code | qwen | qwen | — | — |
| crush | crush | — | — | — |
| copilot-cli | copilot | copilot | — | — |

Nama executable dan argumen di atas diverifikasi saat implementasi untuk agent
yang terpasang (claude, codex). Yang lain dipakai apa adanya dan bisa
dikoreksi dengan mengedit file data.

Agent tambahan pengguna disimpan di Defaults (`agentCustomRules`) dengan bentuk
`{id, displayName, executable}`. Saat ditambahkan dari proses yang berjalan,
`id` dan `displayName` diambil dari nama executable.

### 5.8 Logo (`AgentIconProvider`)

Urutan sumber:

1. `~/.mynotch/icons/<id>.png` bila ada (gambar pilihan pengguna disalin ke
   sini).
2. Ikon app dari `appBundleIDs` pertama yang terpasang, lewat helper
   `AppIconAsNSImage(for:)` yang sudah ada.
3. SF Symbol `sparkles`.

Hasil di-cache per `id` dan dibuang saat file di folder ikon berubah.
Codex tidak punya app di laptop ini; logonya memakai jalur 1 begitu file
`codex.png` tersedia, dan sampai saat itu jalur 3.

### 5.9 `HookInstaller`

Logika gabung JSON murni di `AgentMonitorKit`; baca/tulis file di lapis app.

Pasang:

1. Salin skrip ke `~/.mynotch/bin/notch-report` (mode `0700`).
2. Untuk setiap agent ber-hooks yang file konfigurasinya ada, buat cadangan
   `<file>.mynotch-backup-<timestamp>`.
3. Tambahkan satu grup hook per event yang dibutuhkan, dengan perintah
   `~/.mynotch/bin/notch-report <id> <Event>` dan `timeout` 5 detik. Grup yang
   perintahnya sudah ada tidak ditambah lagi.
4. Validasi hasilnya sebagai JSON lalu tulis secara atomik. Bila gagal, file
   asli tidak disentuh dan error ditampilkan di Settings.

Event yang dipasang:

- Claude Code: `SessionStart`, `UserPromptSubmit`, `PostToolUse`,
  `Notification`, `Stop`, `SubagentStop`, `SessionEnd`, ditambah
  `SubagentStart` dan `StopFailure` bila rekaman payload (5.2) menunjukkan
  versi terpasang mendukungnya.
- Codex: `SessionStart`, `UserPromptSubmit`, `PermissionRequest`,
  `PostToolUse`, `Stop`, `SubagentStop`.

Hooks dan pengaturan lain di file itu, termasuk `notify` di
`~/.codex/config.toml`, tidak diubah. Codex menyimpan status kepercayaan hook
di `[hooks.state]`; setelah pemasangan, Codex mungkin meminta persetujuan sekali.
Settings menampilkan catatan tentang hal ini.

Lepas: hapus hanya grup hook yang perintahnya memanggil
`~/.mynotch/bin/notch-report`.

### 5.10 Integrasi ke kode yang ada

| File | Perubahan |
|---|---|
| `enums/generic.swift` | `NotchViews.agents` |
| `components/Notch/BoringHeader.swift` | tampilkan `TabSelectionView()` bila Shelf atau `agentMonitorEnabled` aktif (bukan hanya saat `boringShelf` aktif) |
| `components/Tabs/TabSelectionView.swift` | daftar tab dinamis: Home selalu ada, Shelf bila `Defaults[.boringShelf]`, Agents bila `Defaults[.agentMonitorEnabled]`; reset `coordinator.currentView = .home` bila `agentMonitorEnabled` dimatikan saat berada di tab `.agents` |
| `ContentView.swift` | `case .agents: AgentsTabView()`; cabang notch tertutup untuk `expandingView.type == .agent`; dismiss notice saat hover/tap |
| `BoringViewCoordinator.swift` | `SneakContentType.agent`; `ExpandedItem.agent: AgentNotice?`; durasi diambil dari `AgentNotice` |
| `sizing/matters.swift` | `agentNoticeWidth` (`540`) |
| `models/Constants.swift` | key Defaults di bawah |
| `boringNotchApp.swift` | menyalakan `AgentMonitorManager` saat launch bila diaktifkan; memasang closure `notchContextProvider` yang membaca `vm` atau `viewModels.values` sesuai mode `showOnAllDisplays` |
| `components/Settings/SettingsView.swift` | entri navigasi ke `AgentsSettingsView` (file terpisah) |

Key Defaults baru: `agentMonitorEnabled` (true), `agentNotifyWaiting` (true),
`agentNotifyError` (true), `agentNotifyDone` (true), `agentCustomRules` ([]).

File baru:

- `AgentMonitorKit/` (paket): `Package.swift`, `Sources/AgentMonitorKit/`
  (`Models.swift`, `InboxEvent.swift`, `JSONValue.swift`,
  `ClaudeFormatAdapter.swift`, `AgentState.swift`, `NotificationPolicy.swift`,
  `ProcessMatcher.swift`, `AgentRegistry.swift`, `HookConfigMerger.swift`,
  `Resources/agents.json`, `Resources/notch-report.sh`),
  `Tests/AgentMonitorKitTests/` beserta fixture.
- `boringNotch/managers/AgentMonitor/`: `AgentMonitorManager.swift`,
  `InboxWatcher.swift`, `ProcessScanner.swift`, `HostAppResolver.swift`,
  `AgentIconProvider.swift`, `HookInstallerService.swift`.
- `boringNotch/components/Agents/`: `AgentsTabView.swift`, `AgentRowView.swift`,
  `AgentNoticeView.swift`.
- `boringNotch/components/Settings/AgentsSettingsView.swift`.

## 6. Penanganan error

- `notch-report` tidak pernah gagal dari sudut pandang agent (selalu exit 0,
  tanpa output).
- File inbox rusak, tidak dikenal, terlalu besar, atau basi: dilewati, dicatat,
  dihapus; file lain tetap diproses.
- Folder inbox hilang saat app berjalan: dibuat ulang dan watcher dipasang ulang.
- Pemindaian proses gagal: state terakhir dipertahankan.
- Pemasangan hooks gagal: file asli utuh, pesan error di Settings, cadangan
  tetap ada.
- Event dengan `session_id` yang belum dikenal selain `SessionStart`: sesi baru
  dibuat (agent yang sudah berjalan sebelum notch menyala tetap tertangkap).

## 7. Keamanan dan privasi

- `~/.mynotch`, `inbox`, `bin`, `icons` dibuat dengan izin `0700`.
- Watcher menolak symlink dan file yang pemiliknya bukan user saat ini.
- Payload diperlakukan sebagai data: tidak dieksekusi, tidak diinterpretasikan
  sebagai perintah, dan teks yang ditampilkan dipotong.
- Yang disimpan di memori hanya: status, nama folder, potongan pesan izin, dan
  nama tool. Teks prompt dan isi tool dibuang. File inbox dihapus segera
  setelah dibaca.
- Tidak ada data yang dikirim ke luar laptop. Pengiriman ke Discord adalah
  fitur terpisah dengan pengaturan eksplisit.

## 8. Testing

Swift Testing (`@Test`, `#expect`) di `AgentMonitorKit`, dijalankan dengan
`swift test`. Modul `Testing` dan `XCTest` tidak ada di Command Line Tools
(sudah dicoba di laptop ini, 2026-11-25), jadi test membutuhkan Xcode
terpasang.

- Adapter: fixture payload asli hasil rekaman dari Claude Code dan Codex
  (dengan isi sensitif disamarkan) untuk setiap event di tabel 5.2.
- Reducer: transisi status, penggabungan hooks dan scan, `SessionEnd`, PID mati,
  hitungan subagent tidak negatif.
- `NotificationPolicy` dan `NoticeQueue`: aturan tampil/tidak, durasi,
  penggabungan per sesi, urutan.
- `ProcessMatcher`: nama persis, peka huruf besar-kecil (`Claude` ≠ `claude`),
  pencocokan lewat interpreter.
- `HookConfigMerger`: menambah ke file kosong, ke file dengan hooks lain,
  idempoten, melepas hanya entri milik notch.
- `notch-report`: test menjalankan skrip lewat `Process` dengan stdin contoh,
  argumen tidak valid, dan stdin kosong, lalu memeriksa file hasilnya.

Target cakupan baris untuk `AgentMonitorKit`: ≥ 80%.

Uji manual di app (setelah Xcode tersedia):

1. Jalankan sesi Claude Code dari app Claude, pindah ke app lain.
2. Minta perintah yang butuh izin → notifikasi amber muncul.
3. Setujui → status kembali "berjalan" di tab Agents.
4. Tunggu jawaban selesai → notifikasi hijau muncul.
5. Ulangi saat app Claude frontmost → tidak ada notifikasi.
6. Jalankan `codex` di Terminal → muncul di tab; ulangi langkah 2–4.
7. Jalankan agent tanpa hooks (atau proses dari daftar tambahan) → muncul
   sebagai "Terdeteksi dari proses".
8. Tutup sesi → baris hilang dalam 5 detik.
9. Putar musik, ulangi langkah 2 → notifikasi tampil, lalu live activity musik
   kembali.

## 9. Build pribadi

- Bundle ID app: `local.mynotch.boringnotch`; XPC helper:
  `local.mynotch.boringnotch.BoringNotchXPCHelper`. Nama layanan helper juga
  ditulis langsung di kode dan ikut diganti:
  `boringNotch/XPCHelperClient/XPCHelperClient.swift:8` dan
  `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift:28`.
- Signing: "Sign to Run Locally", tanpa development team.
- Sparkle: `SUEnableDownloaderService`, `SUEnableInstallerLauncherService`, `SUFeedURL`, dan `SUPublicEDKey` dihapus dari `Info.plist`, updater
  tidak dijalankan, dan menu "Check for Updates" disembunyikan.
- Konsekuensi: pengaturan build ini terpisah dari app resmi, dan app resmi
  harus di-quit saat build ini berjalan.
- Repo resmi tersedia sebagai remote `upstream`; pembaruan resmi diambil dengan
  rebase branch `mynotch`.
- Build dan test membutuhkan Xcode terpasang dan dipilih lewat
  `xcode-select`.
