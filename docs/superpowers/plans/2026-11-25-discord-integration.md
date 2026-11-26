# Discord Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menghubungkan MyNotch ke Discord desktop lokal via IPC untuk menampilkan Rich Presence Apple Music (`Listening`) di profil pengguna serta status & kontrol cepat Voice Call Discord di notch.

**Architecture:** Logika murni (framing biner IPC, pemformatan Apple Music Rich Presence, model & reducer `DiscordVoiceState`) berada di `AgentMonitorKit/Sources/AgentMonitorKit/Discord/` dan diuji lewat `swift test`. Lapis app yang tipis (`KeychainSecretStore`, `AppleMusicArtworkResolver`, `DiscordOAuthService`, `DiscordIPCClient`, `DiscordIntegrationManager`, UI Voice di notch, dan `DiscordSettingsView`) berada di `boringNotch` dan terhubung ke `MusicManager.shared`.

**Tech Stack:** Swift 6 tools (`AgentMonitorKit`), Swift 5 mode app (macOS 14+), Darwin POSIX `AF_UNIX` sockets, `Security` framework (Keychain), `URLSession`, SwiftUI, `Defaults`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-25-discord-integration-design.md`

## Global Constraints

- Semua pekerjaan di branch `mynotch`; remote `origin` (`zakyirsyaad/mynotch`), `upstream` tidak pernah di-push.
- Kedua fitur Discord **opt-in** (default `false`).
- `client_secret`, `access_token`, dan `refresh_token` hanya disimpan di macOS Keychain (`local.mynotch.boringnotch`), tidak pernah di `Defaults` atau `os.Logger`.
- Cakupan baris `AgentMonitorKit` tetap ≥ 80% di CI (`swift test --enable-code-coverage`).
- Setiap commit harus lolos `swift test` dan `xcodebuild` di GitHub Actions (`mynotch-ci.yml`).

---

### Task 1: `DiscordIPCFramer` di `AgentMonitorKit`

**Files:**
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/Discord/DiscordIPCFramer.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/DiscordIPCFramerTests.swift`

**Interfaces:**
- Produces:
  - `public enum DiscordIPCOpcode: UInt32, Sendable, Equatable { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }`
  - `public struct DiscordIPCFrame: Sendable, Equatable { public let opcode: DiscordIPCOpcode; public let payload: Data }`
  - `public enum DiscordIPCError: Error, Equatable, Sendable { case unknownOpcode(UInt32), payloadTooLarge(Int), malformedJSON }`
  - `public enum DiscordIPCFramer`:
    - `static let maxFramePayloadBytes = 1_048_576`
    - `static func encode(opcode: DiscordIPCOpcode, payload: Data) -> Data`
    - `static func encodeJSON(_ value: JSONValue, opcode: DiscordIPCOpcode = .frame) throws -> Data`
    - `static func decodeNextFrame(from buffer: inout Data) throws -> DiscordIPCFrame?`
    - `static func handshakePayload(clientID: String) -> JSONValue`
    - `static func setActivityPayload(pid: Int32, nonce: String, activity: DiscordPresenceActivity?) -> JSONValue`
    - `static func authorizePayload(clientID: String, scopes: [String], nonce: String) -> JSONValue`
    - `static func authenticatePayload(accessToken: String, nonce: String) -> JSONValue`
    - `static func subscribePayload(event: String, nonce: String) -> JSONValue`
    - `static func getSelectedVoiceChannelPayload(nonce: String) -> JSONValue`
    - `static func getVoiceSettingsPayload(nonce: String) -> JSONValue`
    - `static func setVoiceSettingsPayload(mute: Bool?, deaf: Bool?, nonce: String) -> JSONValue`
    - `static func selectVoiceChannelPayload(channelID: String?, nonce: String) -> JSONValue`

- [ ] **Step 1: Tulis test yang gagal (`DiscordIPCFramerTests.swift`)**
  - Uji round-trip `encode` → `decodeNextFrame` (8-byte little-endian header + payload), termasuk dua frame berurutan dalam satu buffer.
  - Uji buffer parsial mengembalikan `nil` dan tidak mengubah `buffer`.
  - Uji payload melebihi `maxFramePayloadBytes` dan opcode invalid melempar `DiscordIPCError`.
  - Uji semua builder payload RPC (`HANDSHAKE`, `SET_ACTIVITY` dengan & tanpa activity, `AUTHORIZE`, `AUTHENTICATE`, `SUBSCRIBE`, `SET_VOICE_SETTINGS`, `SELECT_VOICE_CHANNEL(nil)`).

- [ ] **Step 2: Implementasi `DiscordIPCFramer.swift`**
  - Gunakan `Data` slicing yang aman untuk `startIndex` non-nol dan encode JSON via `JSONEncoder`.

- [ ] **Step 3: Verifikasi**
  - Run `cd AgentMonitorKit && swift build` (lokal) dan `swift test --filter DiscordIPCFramerTests` (CI).

---

### Task 2: `DiscordMusicPresenceFormatter` di `AgentMonitorKit`

**Files:**
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/Discord/DiscordMusicPresenceFormatter.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/DiscordMusicPresenceFormatterTests.swift`

**Interfaces:**
- Produces:
  - `public struct DiscordMusicTrack: Sendable, Equatable` (`title`, `artist`, `album`, `duration`, `elapsed`, `timestampDate`, `playbackRate`, `isPlaying`, `bundleIdentifier`, `artworkURL`)
  - `public struct DiscordPresenceActivity: Sendable, Equatable { public let type: Int; public let details: String; public let state: String; public let startTimestamp: Int?; public let endTimestamp: Int?; public let largeImage: String?; public let largeText: String? }` dengan `func toJSONValue() -> JSONValue`
  - `public enum DiscordMusicPresenceFormatter { public static func activity(from track: DiscordMusicTrack?, enabled: Bool, now: Date) -> DiscordPresenceActivity? }`

- [ ] **Step 1: Tulis test yang gagal (`DiscordMusicPresenceFormatterTests.swift`)**
  - Apple Music (`com.apple.Music`, `isPlaying: true`) menghasilkan `type == 2`, `details == title`, `state == artist`, `largeText == album`, `startTimestamp`, dan `endTimestamp`.
  - Track `nil`, `enabled == false`, `isPlaying == false`, judul kosong, atau `bundleIdentifier` selain `com.apple.Music` mengembalikan `nil`.
  - Perhitungan `endTimestamp` memperhitungkan `elapsed`, `now - timestampDate`, `playbackRate`, dan `duration`.

- [ ] **Step 2: Implementasi `DiscordMusicPresenceFormatter.swift`**

- [ ] **Step 3: Verifikasi**
  - Run `swift build` dan `swift test --filter DiscordMusicPresenceFormatterTests`.

---

### Task 3: `DiscordVoiceState` & Reducer di `AgentMonitorKit`

**Files:**
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/Discord/DiscordVoiceState.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/DiscordVoiceStateTests.swift`

**Interfaces:**
- Consumes: `JSONValue`
- Produces:
  - `public struct DiscordVoiceState: Sendable, Equatable` (`channelID: String?`, `channelName: String?`, `isMuted: Bool`, `isDeafened: Bool`, `speakingUserIDs: Set<String>`, `currentUserID: String?`, `isInVoice`, `isAnyoneSpeaking`, `isSelfSpeaking`)
  - `public enum DiscordVoiceReducer { public static func reducing(_ state: DiscordVoiceState, message: JSONValue) -> DiscordVoiceState }`

- [ ] **Step 1: Tulis test yang gagal (`DiscordVoiceStateTests.swift`)**
  - Uji `READY` (`evt == "READY"`) menyimpan `currentUserID`.
  - Uji `GET_SELECTED_VOICE_CHANNEL` dan `VOICE_CHANNEL_SELECT` masuk channel, pindah channel (membersihkan `speakingUserIDs`), dan keluar channel (`data` null atau `channel_id` null).
  - Uji `GET_VOICE_SETTINGS` dan `VOICE_SETTINGS_UPDATE` memperbarui `isMuted` dan `isDeafened`.
  - Uji `SPEAKING_START` / `SPEAKING_STOP` menambah & menghapus `user_id` di `speakingUserIDs`, serta `isSelfSpeaking`.

- [ ] **Step 2: Implementasi `DiscordVoiceState.swift`**

- [ ] **Step 3: Verifikasi**
  - Run `swift build` dan `swift test --filter DiscordVoiceStateTests`.
  - Commit `AgentMonitorKit`: `feat(discord): add Discord IPC framer, Apple Music presence formatter, and voice state reducer`.

---

### Task 4: Lapis App — Keychain, Artwork, OAuth2, IPC Client, & Manager

**Files:**
- Create: `boringNotch/managers/Discord/KeychainSecretStore.swift`
- Create: `boringNotch/managers/Discord/AppleMusicArtworkResolver.swift`
- Create: `boringNotch/managers/Discord/DiscordOAuthService.swift`
- Create: `boringNotch/managers/Discord/DiscordIPCClient.swift`
- Create: `boringNotch/managers/Discord/DiscordIntegrationManager.swift`
- Modify: `boringNotch.xcodeproj/project.pbxproj` (tambah folder tersinkron `managers/Discord` dan `components/Discord`, serta file `DiscordSettingsView.swift`)

- [ ] **Step 1: Implementasi `KeychainSecretStore.swift` & `AppleMusicArtworkResolver.swift`**
  - `KeychainSecretStore`: pembungkus `Security.framework` (`save`, `load`, `delete`) untuk `client_secret`, `access_token`, dan `refresh_token`.
  - `AppleMusicArtworkResolver`: actor/cache in-memory ringan yang menanyakan `https://itunes.apple.com/search` (`media=music&entity=song&limit=1`) untuk mendapatkan URL artwork `512x512` HTTPS berdasarkan `artist + songTitle` (dengan deduplikasi agar tidak spam).

- [ ] **Step 2: Implementasi `DiscordOAuthService.swift`**
  - Tukar `code` hasil RPC `AUTHORIZE` ke `https://discord.com/api/oauth2/token` (`grant_type=authorization_code`) dan `refresh_token` otomatis.

- [ ] **Step 3: Implementasi `DiscordIPCClient.swift`**
  - Cari socket `discord-ipc-0..9` di `NSTemporaryDirectory()` dan `/tmp/`, cek `lstat` (`S_ISSOCK`, `st_uid == getuid()`).
  - Kelola `DispatchSourceRead` / read thread di `DispatchQueue` utilitas: kirim `HANDSHAKE`, terima `READY` & `DISPATCH`, balas `PING` dengan `PONG`, tangani disconnect dengan backoff (2s..30s).
  - Callback `@MainActor` untuk perubahan koneksi (`DiscordIPCConnectionState`) dan pesan `JSONValue` masuk.

- [ ] **Step 4: Implementasi `DiscordIntegrationManager.swift`**
  - `@MainActor final class DiscordIntegrationManager: ObservableObject`.
  - Published: `connectionState`, `voiceState: DiscordVoiceState`, `isVoiceAuthorized: Bool`, `authError: String?`.
  - Observasi `MusicManager.shared` (`$songTitle`, `$artistName`, `$album`, `$isPlaying`, `$isPlayerIdle`, `$bundleIdentifier`, `$songDuration`, `$elapsedTime`, `$timestampDate`) dan `Defaults` untuk mengirim `SET_ACTIVITY` melalui `DiscordMusicPresenceFormatter.activity(...)`.
  - Jika `discordVoiceEnabled == true` dan `access_token` tersedia di Keychain, otomatis kirim `AUTHENTICATE` setelah `READY`, lalu subscribe `VOICE_CHANNEL_SELECT`, `VOICE_SETTINGS_UPDATE`, `SPEAKING_START`, `SPEAKING_STOP`, serta fetch `GET_SELECTED_VOICE_CHANNEL` dan `GET_VOICE_SETTINGS`.
  - Aksi UI: `authorizeVoiceRPC()`, `disconnectVoiceAuth()`, `toggleMute()`, `toggleDeafen()`, `leaveVoiceChannel()`, `openDiscordApp()`.

- [ ] **Step 5: Daftarkan folder & file baru di `project.pbxproj`**
  - Tambah `PBXFileSystemSynchronizedRootGroup` untuk `managers/Discord` dan `components/Discord`, serta `DiscordSettingsView.swift`.

---

### Task 5: UI Voice Discord di Notch

**Files:**
- Create: `boringNotch/components/Discord/DiscordVoiceLiveActivityView.swift`
- Create: `boringNotch/components/Discord/DiscordVoiceBarView.swift`
- Modify: `boringNotch/ContentView.swift` (cabang voice di `computedChinWidth` dan `NotchLayout()`)
- Modify: `boringNotch/components/Notch/NotchHomeView.swift` (sisipkan `DiscordVoiceBarView` saat `voiceState.isInVoice`)

- [ ] **Step 1: Implementasi `DiscordVoiceLiveActivityView.swift`**
  - Mengikuti proporsi simetris `MusicLiveActivity()` di `ContentView.swift` (`effectiveClosedNotchHeight - 12`, sekitar `20×20 pt` per sayap):
    - Sayap kiri: ikon status voice (`mic.fill` hijau, `mic.slash.fill` merah saat muted, `headphones` merah saat deafened).
    - Tengah: `Rectangle().fill(.black).frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)`.
    - Sayap kanan: indikator spektrum suara 3 batang saat `isAnyoneSpeaking` atau titik redup saat hening.

- [ ] **Step 2: Implementasi `DiscordVoiceBarView.swift`**
  - Bar monokrom kompak untuk notch terbuka (`Color.white.opacity(0.06)`, radius `10`, mengikuti `AgentRowView`): ikon voice (`22×22 pt`) + nama channel + status `"Berbicara · Discord"` (klik membuka Discord), serta tiga tombol ikon bulat `30×30 pt` (**Mute**, **Deafen**, **Leave**).

- [ ] **Step 3: Integrasikan ke `ContentView.swift` & `NotchHomeView.swift`**
  - Di `ContentView.swift`: tampilkan `DiscordVoiceLiveActivityView` saat `discordManager.voiceState.isInVoice && Defaults[.discordVoiceEnabled] && vm.notchState == .closed && !vm.hideOnClosed` (setelah cabang baterai, agent notice, dan inline HUD, serta sebelum cabang musik) dan tambahkan kondisi yang sama di `computedChinWidth`.
  - Di `NotchHomeView.swift`: tampilkan `DiscordVoiceBarView()` di bagian atas saat `discordManager.voiceState.isInVoice && Defaults[.discordVoiceEnabled]`.

---

### Task 6: Settings Discord, Wiring App, & Verifikasi CI

**Files:**
- Create: `boringNotch/components/Settings/DiscordSettingsView.swift`
- Modify: `boringNotch/models/Constants.swift` (`discordApplicationID`, `discordAppleMusicPresenceEnabled`, `discordVoiceEnabled`)
- Modify: `boringNotch/boringNotchApp.swift` (`start()` dan `stop()` `DiscordIntegrationManager.shared`)
- Modify: `boringNotch/components/Settings/SettingsView.swift` (entri navigasi `"Discord"` → `DiscordSettingsView()`)

- [ ] **Step 1: Tambah key `Defaults` di `Constants.swift`**
- [ ] **Step 2: Buat `DiscordSettingsView.swift`**
  - Seksi Koneksi Discord (Application ID, `SecureField` Client Secret di Keychain, status IPC, catatan Redirect URI `http://127.0.0.1`).
  - Seksi Apple Music Rich Presence (saklar `"Tampilkan lagu Apple Music di profil"`).
  - Seksi Voice di Notch (saklar aktif, status otorisasi, tombol Hubungkan / Putuskan Otorisasi).
- [ ] **Step 3: Sambungkan ke `SettingsView.swift` & `boringNotchApp.swift`**
- [ ] **Step 4: Lint, push, dan verifikasi GitHub Actions**
  - Run `plutil -lint boringNotch.xcodeproj/project.pbxproj`.
  - Commit & push ke `origin/mynotch`.
  - Pastikan semua test `AgentMonitorKit` lulus (coverage ≥ 80%) dan `xcodebuild` Release build sukses.
- [ ] **Step 5: Uji manual di Mac**
  - Jalankan checklist bagian 7 spec.
