# Integrasi Discord — Desain

Tanggal: 2026-11-25
Branch: `mynotch` (fork pribadi boring.notch, tidak untuk upstream)
Status: draf, menunggu review

## 1. Tujuan

Menghubungkan MyNotch dengan aplikasi Discord desktop lokal melalui Discord IPC untuk dua hal:

1. **Rich Presence Apple Music**: menampilkan lagu Apple Music yang sedang diputar (`Listening` dengan progress bar dan sampul album) di profil Discord pengguna.
2. **Status Voice Discord di notch**: menampilkan status ketika pengguna sedang berada di voice channel Discord (nama channel, indikator bicara, status mute/deafen) beserta kontrol cepat (Mute, Deafen, Leave) di notch terbuka.

Kriteria berhasil:

- Saat Apple Music memutar lagu dan fitur diaktifkan, profil Discord pengguna menampilkan aktivitas `Listening` (`type: 2`) dengan judul, artis, nama album, dan progress bar live; saat lagu dijeda atau berhenti, aktivitas otomatis dibersihkan.
- Saat pengguna masuk ke voice channel Discord, notch tertutup menampilkan live activity voice (proporsi simetris `20×20 pt` per sayap) dan notch terbuka menyediakan bar kontrol cepat Mute, Deafen, dan Leave.
- Tidak membutuhkan server bot eksternal atau library pihak ketiga; semua komunikasi IPC berjalan lokal lewat Unix domain socket Discord (`discord-ipc-0..9`).
- Kedua fitur bersifat **opt-in** (mati secara default), dan kredensial OAuth (`client_secret`, `access_token`, `refresh_token`) disimpan aman di macOS Keychain.

## 2. Ruang lingkup

Termasuk:

- **Rich Presence Apple Music** lewat Discord Local IPC (`HANDSHAKE` + `SET_ACTIVITY`) dengan data track dari `MusicManager` (`type: 2` Listening + artwork via iTunes Search API cache).
- **Status & Kontrol Voice Discord** lewat Discord Local RPC (`AUTHORIZE` / `AUTHENTICATE`, subscribe event `VOICE_CHANNEL_SELECT`, `VOICE_SETTINGS_UPDATE`, `SPEAKING_START`, `SPEAKING_STOP`, serta perintah `GET_SELECTED_VOICE_CHANNEL`, `GET_VOICE_SETTINGS`, `SET_VOICE_SETTINGS`, `SELECT_VOICE_CHANNEL`).
- **Tampilan Voice di Notch**:
  - Live activity di notch tertutup (`DiscordVoiceLiveActivityView`).
  - Bar kontrol cepat di notch terbuka (`DiscordVoiceBarView`).
- **Settings → Discord** (`DiscordSettingsView`): pengaturan Application ID & Client Secret (Keychain), saklar Apple Music Presence, saklar Voice di notch, tombol otorisasi Discord RPC, dan indikator status koneksi IPC.

Tidak termasuk:

- Rich Presence AI Agent maupun pengiriman pesan/alert Webhook ke channel Discord.
- Daftar seluruh peserta voice lengkap dengan avatar (cukup nama channel, status mute/deafen pengguna, dan indikator bicara).

## 3. Pengalaman pengguna

### 3.1 Rich Presence Apple Music di Profil Discord

- Sumber lagu: `MusicManager.shared` ketika `isPlaying == true`, `!isPlayerIdle`, dan sumber pemutar adalah Apple Music (`bundleIdentifier == "com.apple.Music"` atau `Defaults[.mediaController] == .appleMusic`).
- Payload `SET_ACTIVITY` memakai aktivitas tipe **Listening** (`type: 2`):
  - `details`: judul lagu (`songTitle`).
  - `state`: nama artis (`artistName`).
  - `assets.large_text`: nama album (`album`).
  - `assets.large_image`: URL sampul album HTTPS (resolusi `512×512`) dari cache lokal `AppleMusicArtworkResolver` (lookup ringan ke iTunes Search API `https://itunes.apple.com/search`). Bila tidak ditemukan, tampil tanpa gambar.
  - `timestamps`: `start` dan `end` berbasis `elapsedTime`, `timestampDate`, `songDuration`, dan `playbackRate` agar Discord menampilkan progress bar berjalan secara live.
- Saat lagu dijeda, berhenti, atau pemutar bukan Apple Music, kirim `SET_ACTIVITY` dengan `activity: null` untuk membersihkan profil Discord.

### 3.2 Status Voice Discord di Notch

- **Notch tertutup** (tampil ketika pengguna sedang terhubung ke voice channel, `discordVoiceEnabled == true`, `!vm.hideOnClosed`, dan tidak tertutup oleh notifikasi prioritas lebih tinggi seperti baterai, agent notice, atau inline HUD):
  - Mengikuti proporsi simetris `MusicLiveActivity` (`effectiveClosedNotchHeight - 12`, sekitar `20×20 pt` per sayap di kiri & kanan notch fisik tanpa teks panjang yang melebar):
    - **Sayap kiri**: ikon mikrofon hijau (aktif), merah dengan coretan (muted), atau headphone tercoret (deafened).
    - **Sayap kanan**: indikator spektrum audio 3 batang hijau saat ada yang berbicara (`isAnyoneSpeaking`), atau titik abu redup saat hening.
  - Prioritas terhadap musik: saat pengguna sedang berada di voice call Discord, tampilan live activity voice menggantikan live activity musik di notch tertutup. Setelah keluar dari voice channel, live activity musik kembali otomatis.
- **Notch terbuka**:
  - Menampilkan bar monokrom `DiscordVoiceBarView` di bagian atas `NotchHomeView` mengikuti gaya permukaan `AgentRowView` (`Color.white.opacity(0.06)`, corner radius `10`, tanpa border berwarna):
    - Kiri: ikon voice (`22×22 pt`), nama channel, serta subjudul status (`"Berbicara · Discord"`, `"Muted · Discord"`, `"Deafened · Discord"`, atau `"Terhubung · Discord"`) dengan titik status `7 pt`. Klik info channel mengaktifkan aplikasi Discord (`com.hnc.Discord`).
    - Kanan: tiga tombol ikon bulat `30×30 pt` mengikuti `BoringHeader`:
      - **Mute / Unmute** (`mic.fill` / `mic.slash.fill`)
      - **Deafen / Undeafen** (`headphones`, merah lembut saat aktif)
      - **Leave** (`phone.down.fill`, merah solid) — memanggil `SELECT_VOICE_CHANNEL` dengan `channel_id: null`.

### 3.3 Settings → Discord

Menu `"Discord"` di `SettingsView`:

1. **Koneksi Aplikasi Discord (Developer Portal)**:
   - Input **"Discord Application ID"** (`discordApplicationID`, disimpan di `Defaults`).
   - `SecureField` **"Client Secret"** (hanya dibutuhkan untuk fitur Voice RPC OAuth2; disimpan di macOS Keychain).
   - Status koneksi IPC: `Terhubung`, `Menunggu Discord…`, `Nonaktif`, atau pesan error singkat.
   - Catatan singkat cara isi Redirect URI di Discord Developer Portal (`http://127.0.0.1` untuk Local RPC OAuth).
2. **Seksi Rich Presence**:
   - Saklar **"Tampilkan lagu Apple Music di profil"** (`discordAppleMusicPresenceEnabled`, default `false`).
3. **Seksi Voice Call di Notch**:
   - Saklar **"Tampilkan status voice di notch"** (`discordVoiceEnabled`, default `false`).
   - Tombol **"Hubungkan Voice RPC"** / **"Putuskan Otorisasi"** beserta status otorisasi (`Terotorisasi` / `Belum diotorisasi`).
   - Penjelasan singkat: Apple Music Rich Presence tidak butuh OAuth, sedangkan kontrol & status Voice butuh izin satu kali di aplikasi Discord (popup "Authorize" di Discord desktop).

## 4. Arsitektur

Satu koneksi Unix domain socket lokal ke Discord desktop melayani Rich Presence Apple Music dan Voice RPC sekaligus:

```
MusicManager (Apple Music) ──▶ DiscordMusicPresenceFormatter ──┐
                                                               ▼
Discord Desktop (discord-ipc-0..9) ◀═══ DiscordIPCClient ◀═══ DiscordIntegrationManager
   │  (events: VOICE_CHANNEL_SELECT,     ▲ (OAuth token)            │
   │   VOICE_SETTINGS_UPDATE, SPEAKING)  └── DiscordOAuthService    ▼
   └────────────────────────────────────▶ DiscordVoiceState ──▶ Notch Voice UI
```

1. **Lapis murni di `AgentMonitorKit/Sources/AgentMonitorKit/Discord/`** (diuji via `swift test`, target cakupan ≥ 80%):
   - `DiscordIPCFramer.swift`: framing biner 8-byte little-endian (`opcode` + `length` + JSON UTF-8) dan builder payload RPC (`HANDSHAKE`, `AUTHORIZE`, `AUTHENTICATE`, `SET_ACTIVITY`, `SUBSCRIBE`, `GET_SELECTED_VOICE_CHANNEL`, `GET_VOICE_SETTINGS`, `SET_VOICE_SETTINGS`, `SELECT_VOICE_CHANNEL`).
   - `DiscordMusicPresenceFormatter.swift`: konversi `DiscordMusicTrack` (Apple Music `type: 2` Listening) → `DiscordPresenceActivity?` dengan perhitungan timestamp `start`/`end`.
   - `DiscordVoiceState.swift`: model immutable `DiscordVoiceState` + reducer murni yang mem-parsing JSON response/dispatch RPC dari Discord (`READY`, `GET_SELECTED_VOICE_CHANNEL`, `VOICE_CHANNEL_SELECT`, `GET_VOICE_SETTINGS`, `VOICE_SETTINGS_UPDATE`, `SPEAKING_START`, `SPEAKING_STOP`).
2. **Lapis app di `boringNotch/managers/Discord/` & `boringNotch/components/Discord/`**:
   - `KeychainSecretStore.swift`: pembungkus `Security.framework` untuk `discord-client-secret`, `discord-access-token`, dan `discord-refresh-token`.
   - `AppleMusicArtworkResolver.swift`: lookup + cache URL sampul album HTTPS `512×512` via iTunes Search API untuk Rich Presence Apple Music.
   - `DiscordOAuthService.swift`: pertukaran `code` dari RPC `AUTHORIZE` ke `https://discord.com/api/oauth2/token` serta refresh token otomatis saat `access_token` kedaluwarsa.
   - `DiscordIPCClient.swift`: klien POSIX `AF_UNIX` socket non-blocking di `DispatchQueue` utilitas dengan handshake, heartbeat `PING`→`PONG`, pengiriman command ber-nonce, streaming event `DISPATCH`, dan reconnect *exponential backoff* (2s..30s).
   - `DiscordIntegrationManager.swift`: `@MainActor ObservableObject` singleton yang mengelola siklus koneksi, menyinkronkan Rich Presence dari `MusicManager.shared`, menyimpan `DiscordVoiceState` terkini, dan menyediakan aksi `toggleMute()`, `toggleDeafen()`, `leaveVoiceChannel()`, serta `authorizeVoiceRPC()`.

## 5. Komponen & Kontrak Teknis

### 5.1 `DiscordIPCFramer`

- Header 8 byte: `UInt32` opcode little-endian (`handshake=0`, `frame=1`, `close=2`, `ping=3`, `pong=4`) + `UInt32` panjang payload little-endian.
- Batas frame masuk maksimal 1 MiB (`1_048_576` byte).
- Semua command RPC memakai `cmd`, `args`, `nonce` (dan `evt` untuk `SUBSCRIBE`).

### 5.2 `DiscordVoiceState` & Reducer

```swift
public struct DiscordVoiceState: Sendable, Equatable {
    public let channelID: String?
    public let channelName: String?
    public let isMuted: Bool
    public let isDeafened: Bool
    public let speakingUserIDs: Set<String>
    public let currentUserID: String?

    public var isInVoice: Bool { channelID != nil }
    public var isAnyoneSpeaking: Bool { !speakingUserIDs.isEmpty }
    public var isSelfSpeaking: Bool {
        guard let currentUserID else { return false }
        return speakingUserIDs.contains(currentUserID)
    }
}
```

Reducer `DiscordVoiceReducer.reducing(_ state: DiscordVoiceState, frameJSON: JSONValue) -> DiscordVoiceState`:
- `READY` (`evt == "READY"`): simpan `data.user.id` sebagai `currentUserID`.
- `GET_SELECTED_VOICE_CHANNEL` / `VOICE_CHANNEL_SELECT`:
  - Bila `data` adalah `.null` atau `data["channel_id"]` kosong/null: kosongkan `channelID`, `channelName`, dan `speakingUserIDs`.
  - Bila ada `id`/`channel_id` dan `name`: perbarui `channelID` dan `channelName`; jika pindah channel, bersihkan `speakingUserIDs`.
- `GET_VOICE_SETTINGS` / `VOICE_SETTINGS_UPDATE`:
  - Perbarui `isMuted = data["mute"]`, `isDeafened = data["deaf"]`.
- `SPEAKING_START` / `SPEAKING_STOP`:
  - Tambah atau hapus `data["user_id"]` pada `speakingUserIDs`.

### 5.3 Alur OAuth2 Local RPC (Voice)

- Discord mengizinkan `SET_ACTIVITY` (Rich Presence Apple Music) hanya dengan `Client ID`.
- Untuk membaca channel voice dan mengubah Mute/Deafen/Leave, Discord RPC mewajibkan `AUTHENTICATE` dengan `access_token` berscope `["rpc", "rpc.voice.read", "rpc.voice.write"]`:
  1. App mengirim `{"cmd": "AUTHORIZE", "args": {"client_id": ..., "scopes": ["rpc", "rpc.voice.read", "rpc.voice.write"]}}`.
  2. Discord desktop memunculkan dialog konfirmasi sekali; setelah disetujui, mengembalikan `code`.
  3. `DiscordOAuthService` menukar `code` ke `https://discord.com/api/oauth2/token` menggunakan `client_id`, `client_secret` (dari Keychain), dan `redirect_uri` (`http://127.0.0.1`), lalu menyimpan `access_token` + `refresh_token` di Keychain.
  4. Pada koneksi berikutnya, app langsung mengirim `AUTHENTICATE` dengan `access_token` tersimpan (atau `refresh_token` bila expired) tanpa popup ulang.

### 5.4 Integrasi ke Kode yang Ada

| File | Perubahan |
|---|---|
| `boringNotch/models/Constants.swift` | Tambah key `Defaults`: `discordApplicationID` (`""`), `discordAppleMusicPresenceEnabled` (`false`), `discordVoiceEnabled` (`false`) |
| `boringNotch/ContentView.swift` | Tambah cabang `discord.voiceState.isInVoice` di `computedChinWidth` dan `NotchLayout()` (notch tertutup) |
| `boringNotch/components/Notch/NotchHomeView.swift` | Tampilkan `DiscordVoiceBarView()` di bagian atas saat `discord.voiceState.isInVoice` |
| `boringNotch/boringNotchApp.swift` | Panggil `DiscordIntegrationManager.shared.start()` saat launch & `stop()` saat terminate |
| `boringNotch/components/Settings/SettingsView.swift` | Tambah `NavigationLink` & case `"Discord": DiscordSettingsView()` |
| `boringNotch.xcodeproj/project.pbxproj` | Tambah folder tersinkron `managers/Discord` dan `components/Discord`, serta file `DiscordSettingsView.swift` |

## 6. Penanganan Error & Keamanan

- **Secret**: `client_secret`, `access_token`, dan `refresh_token` hanya disimpan di macOS Keychain (`kSecAttrService = "local.mynotch.boringnotch"`), tidak pernah masuk `Defaults` atau log.
- **IPC Socket**: Sebelum `connect()`, verifikasi `lstat` memastikan path adalah socket (`S_ISSOCK`) milik user aktif (`st_uid == getuid()`).
- **Kegagalan Koneksi**: Jika Discord desktop tidak berjalan atau di-restart, koneksi dicoba ulang dengan backoff 2s → 30s; saat disconnect, `voiceState` di-reset agar indikator voice di notch langsung hilang dan tidak macet.

## 7. Testing

- Unit test di `AgentMonitorKitTests` (target cakupan baris ≥ 80%):
  - `DiscordIPCFramerTests`: encode/decode frame biner, batas ukuran frame, builder command RPC (`HANDSHAKE`, `AUTHORIZE`, `AUTHENTICATE`, `SET_ACTIVITY`, `SUBSCRIBE`, `SET_VOICE_SETTINGS`, `SELECT_VOICE_CHANNEL`).
  - `DiscordMusicPresenceFormatterTests`: `type == 2`, perhitungan `start`/`end` timestamp, paused/idle/non-Apple-Music → `nil`.
  - `DiscordVoiceStateTests`: reducer `READY`, `GET_SELECTED_VOICE_CHANNEL`, `VOICE_CHANNEL_SELECT` (masuk, pindah, keluar/`null`), `VOICE_SETTINGS_UPDATE`, `SPEAKING_START`/`SPEAKING_STOP`.
- Uji manual di Mac (setelah build dari CI):
  1. Isi `Application ID` di Settings → Discord dan nyalakan **Tampilkan lagu Apple Music di profil** → putar lagu di Apple Music → profil Discord menampilkan `Listening` + progress bar + cover album; pause → status bersih.
  2. Isi `Client Secret`, nyalakan **Tampilkan status voice di notch**, klik **Hubungkan Voice RPC**, setujui dialog di Discord desktop.
  3. Masuk ke salah satu voice channel di Discord → notch tertutup menampilkan ikon status mic & spektrum suara; buka notch → tombol Mute, Deafen, dan Leave berfungsi langsung.
  4. Putar musik sambil di voice call → voice tampil; klik Leave → musik kembali tampil di notch tertutup.
