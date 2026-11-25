# Agent Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notch menampilkan notifikasi sementara dan tab daftar untuk semua agent AI yang berjalan di laptop, dari laporan hooks dan pemindaian proses.

**Architecture:** Logika murni (parsing event, adapter, reducer status, kebijakan notifikasi, pencocokan proses, registry, penggabungan konfigurasi hooks) ada di paket Swift lokal `AgentMonitorKit` dan diuji dengan `swift test`. Lapis app yang tipis (watcher folder, pemindai proses, resolver app asal, ikon, installer, UI) ada di target `boringNotch` dan memanggil paket itu. Hooks agent menulis event lewat skrip `notch-report` ke `~/.mynotch/inbox/`.

**Tech Stack:** Swift 5 mode app (target macOS 14), Swift 6 tools untuk paket, SwiftUI, AppKit, libproc/sysctl, `Defaults`, Swift Testing, POSIX `sh`.

**Spec:** `docs/superpowers/specs/2026-11-25-agent-monitor-design.md`

## Global Constraints

- Semua pekerjaan di branch `mynotch`; remote resmi bernama `upstream`, tidak pernah di-push.
- Deployment target app tetap `MACOSX_DEPLOYMENT_TARGET = 14.0`; paket `platforms: [.macOS(.v14)]`.
- Build dan test membutuhkan Xcode terpasang dan dipilih lewat `xcode-select` (Command Line Tools tidak punya `Testing`/`XCTest`).
- Folder data: `~/.mynotch` dengan subfolder `inbox`, `bin`, `icons`, semuanya izin `0700`.
- Skrip pelapor terpasang di `~/.mynotch/bin/notch-report`; dipanggil sebagai `notch-report <source> <event>`.
- Argumen skrip harus cocok `^[A-Za-z0-9_-]{1,64}$`; stdin dibaca maksimal 262144 byte; skrip selalu exit 0 tanpa output.
- Amplop inbox: `{"v":1,"source":…,"event":…,"pid":…,"ts":…,"payload":…}`.
- Watcher: hanya file biasa `.json`, bukan symlink, pemilik user saat ini, ukuran ≤ 300000 byte; event lebih tua dari 600 detik dibuang; file selalu dihapus setelah dibaca.
- Pemindaian proses tiap 5 detik; penelusuran proses induk maksimal 16 langkah.
- Durasi notifikasi: `waiting` 5 detik, `error` 3 detik, `done` 3 detik; `running` tidak memicu notifikasi.
- Lebar notch saat notifikasi agent: 540 pt.
- Teks detail dipotong 80 karakter.
- Warna status: `running` teal, `waiting` amber, `error` merah, `done` hijau.
- Urutan baris tab: `waiting`, `error`, `running`, `done`; dalam status yang sama, `updatedAt` terbaru di atas.
- Key Defaults: `agentMonitorEnabled` (true), `agentNotifyWaiting` (true), `agentNotifyError` (true), `agentNotifyDone` (true), `agentCustomRules` ([]).
- Bundle ID: `local.mynotch.boringnotch` dan `local.mynotch.boringnotch.BoringNotchXPCHelper`.
- Teks prompt dan isi tool dari payload tidak pernah disimpan di model.
- Logging lewat `os.Logger(subsystem: bundleIdentifier, category: "AgentMonitor")`, bukan `print`.
- Model di paket adalah value type immutable; fungsi state mengembalikan state baru.

## Review Focus

1. Beberapa sesi Claude Code di folder proyek yang sama: harus tampil sebagai baris terpisah per `session_id`, bukan saling menimpa. Diuji di Task 4 (`twoSessionsSameCwdStaySeparate`).
2. Notch baru menyala saat agent sudah berjalan: event selain `SessionStart` untuk sesi yang belum dikenal harus membuat sesi baru. Diuji di Task 4 (`unknownSessionCreatedFromAnyStatusEvent`).
3. Agent yang sama terlihat dari hooks dan dari scan proses: tidak boleh muncul dua baris. Diuji di Task 4 (`scanSkipsPidOwnedByHooksSession`) dan Task 6 (`resolveAgentPidWalksPastShell`).
4. File konfigurasi hooks yang sudah berisi hooks plugin lain: entri lain tetap utuh setelah pasang dan lepas. Diuji di Task 7 (`installPreservesForeignHooks`, `uninstallRemovesOnlyOwnEntries`).
5. Pesan izin dengan baris baru, emoji, atau sangat panjang: dipotong di batas grapheme dan baris baru diganti spasi. Diuji di Task 3 (`detailCollapsesNewlinesAndTruncatesGraphemes`).

---

### Task 0: Build pribadi

**Files:**
- Modify: `boringNotch.xcodeproj/project.pbxproj` (semua `PRODUCT_BUNDLE_IDENTIFIER`, `CODE_SIGN_IDENTITY`)
- Modify: `boringNotch/Info.plist:10-17` (hapus `SUEnableDownloaderService`, `SUEnableInstallerLauncherService`, `SUFeedURL`, `SUPublicEDKey`)
- Modify: `boringNotch/XPCHelperClient/XPCHelperClient.swift:8`
- Modify: `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift:28`
- Modify: `boringNotch/boringNotchApp.swift:24-25,39`
- Modify: `boringNotch/components/Settings/SettingsView.swift:906`

**Interfaces:**
- Produces: app bernama sama yang bisa di-build dengan `xcodebuild` tanpa development team.

- [ ] **Step 1: Pastikan Xcode aktif**

Run: `xcodebuild -version`
Expected: mencetak `Xcode <versi>`, bukan error `requires Xcode`. Bila error, pengguna menjalankan `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

- [ ] **Step 2: Ganti bundle ID**

`theboringteam.boringnotch` → `local.mynotch.boringnotch` dan `theboringteam.boringnotch.BoringNotchXPCHelper` → `local.mynotch.boringnotch.BoringNotchXPCHelper` di `project.pbxproj` dan kedua file Swift di atas. Set `CODE_SIGN_IDENTITY = "-"` (Sign to Run Locally) untuk kedua target.

- [ ] **Step 3: Matikan Sparkle**

Hapus `SUEnableDownloaderService`, `SUEnableInstallerLauncherService`, `SUFeedURL`, dan `SUPublicEDKey` dari `Info.plist`. Di `boringNotchApp.swift`, `SPUStandardUpdaterController(startingUpdater: false, …)` dan hapus `CheckForUpdatesView` dari menu bar. Di `SettingsView.swift:906`, hapus `CheckForUpdatesView`. `SettingsWindowController.setUpdaterController` tetap dipanggil supaya tidak ada perubahan tipe.

- [ ] **Step 4: Build**

Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath build/DerivedData build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Jalankan**

Quit app Boring Notch resmi, lalu `open build/DerivedData/Build/Products/Debug/boringNotch.app`.
Expected: notch berfungsi (hover membuka notch); menu bar tidak punya "Check for Updates"; `defaults read local.mynotch.boringnotch` ada.

- [ ] **Step 6: Commit**

```bash
git add boringNotch.xcodeproj boringNotch/Info.plist boringNotch/XPCHelperClient boringNotch/boringNotchApp.swift boringNotch/components/Settings/SettingsView.swift BoringNotchXPCHelper
git commit -m "chore: personal build with own bundle id and no auto-update"
```

Tambahkan `build/` ke `.gitignore` di commit yang sama.

---

### Task 1: Paket `AgentMonitorKit`, amplop inbox, dan skrip `notch-report`

**Files:**
- Create: `AgentMonitorKit/Package.swift`
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/JSONValue.swift`
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/InboxEvent.swift`
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/MyNotchPaths.swift`
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/Resources/notch-report.sh`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/InboxEventTests.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/NotchReportScriptTests.swift`

**Interfaces:**
- Produces:
  - `public enum JSONValue: Sendable, Equatable, Codable { case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue]) }` dengan `subscript(key: String) -> JSONValue?` dan `var stringValue: String?`
  - `public struct InboxEvent: Sendable, Equatable { let version: Int; let source: String; let event: String; let pid: Int32; let timestamp: Date; let payload: JSONValue }`
  - `public enum InboxDecodeError: Error, Equatable { case malformed, unsupportedVersion(Int) }`
  - `public static func InboxEvent.decode(_ data: Data) throws(InboxDecodeError) -> InboxEvent`
  - `public struct MyNotchPaths: Sendable { init(home: URL); let root, inbox, bin, icons, reporter: URL }`
  - `public enum NotchReportScript { public static var url: URL }` (dari `Bundle.module`)

- [ ] **Step 1: Buat `Package.swift`**

`// swift-tools-version:6.0`, nama `AgentMonitorKit`, `platforms: [.macOS(.v14)]`, satu library product, target dengan `resources: [.copy("Resources")]`, test target dengan `resources: [.copy("Fixtures")]` (folder `Fixtures` dibuat kosong dengan `.gitkeep`).

- [ ] **Step 2: Tulis test amplop yang gagal**

```swift
import Testing
import Foundation
@testable import AgentMonitorKit

@Test func decodesEnvelope() throws {
    let json = #"{"v":1,"source":"claude-code","event":"Stop","pid":42,"ts":1764062000,"payload":{"session_id":"abc"}}"#
    let event = try InboxEvent.decode(Data(json.utf8))
    #expect(event.source == "claude-code")
    #expect(event.event == "Stop")
    #expect(event.pid == 42)
    #expect(event.timestamp == Date(timeIntervalSince1970: 1764062000))
    #expect(event.payload["session_id"]?.stringValue == "abc")
}

@Test func nullPayloadAccepted() throws {
    let json = #"{"v":1,"source":"codex","event":"Stop","pid":1,"ts":0,"payload":null}"#
    #expect(try InboxEvent.decode(Data(json.utf8)).payload == .null)
}

@Test func rejectsUnknownVersion() {
    let json = #"{"v":2,"source":"x","event":"Stop","pid":1,"ts":0,"payload":null}"#
    #expect(throws: InboxDecodeError.unsupportedVersion(2)) { try InboxEvent.decode(Data(json.utf8)) }
}

@Test func rejectsGarbage() {
    #expect(throws: InboxDecodeError.malformed) { try InboxEvent.decode(Data("not json".utf8)) }
}
```

- [ ] **Step 3: Jalankan, pastikan gagal**

Run: `cd AgentMonitorKit && swift test --filter InboxEventTests`
Expected: FAIL kompilasi, `cannot find 'InboxEvent' in scope`.

- [ ] **Step 4: Implementasi `JSONValue`, `InboxEvent`, `MyNotchPaths`**

`JSONValue` memakai `singleValueContainer` (urutan coba: nil, Bool, Double, String, array, object). `MyNotchPaths(home:)`: `root = home/.mynotch`, `inbox = root/inbox`, `bin = root/bin`, `icons = root/icons`, `reporter = bin/notch-report`.

- [ ] **Step 5: Jalankan, pastikan lulus**

Run: `swift test --filter InboxEventTests`
Expected: 4 test PASS.

- [ ] **Step 6: Tulis test skrip yang gagal**

Helper test `runReporter(args: [String], stdin: String, home: URL) -> (exitCode: Int32, stdout: String)` menjalankan `/bin/sh NotchReportScript.url.path …` lewat `Process` dengan `HOME` diarahkan ke folder sementara.

```swift
@Test func writesEnvelopeWithPayload() throws {
    let home = try makeTempHome()
    let result = try runReporter(args: ["claude-code", "Stop"], stdin: #"{"session_id":"s1"}"#, home: home)
    #expect(result.exitCode == 0)
    #expect(result.stdout.isEmpty)
    let files = try inboxFiles(home)
    #expect(files.count == 1)
    let event = try InboxEvent.decode(Data(contentsOf: files[0]))
    #expect(event.source == "claude-code")
    #expect(event.payload["session_id"]?.stringValue == "s1")
}

@Test func emptyStdinBecomesNull() throws {
    let home = try makeTempHome()
    _ = try runReporter(args: ["codex", "Stop"], stdin: "", home: home)
    #expect(try InboxEvent.decode(Data(contentsOf: inboxFiles(home)[0])).payload == .null)
}

@Test func invalidArgumentWritesNothing() throws {
    let home = try makeTempHome()
    let result = try runReporter(args: [#"bad"name"#, "Stop"], stdin: "{}", home: home)
    #expect(result.exitCode == 0)
    #expect(try inboxFiles(home).isEmpty)
}

@Test func inboxCreatedPrivate() throws {
    let home = try makeTempHome()
    _ = try runReporter(args: ["codex", "Stop"], stdin: "{}", home: home)
    let perms = try FileManager.default.attributesOfItem(atPath: MyNotchPaths(home: home).inbox.path)[.posixPermissions] as? Int
    #expect(perms == 0o700)
}

@Test func noTempFilesLeftBehind() throws {
    let home = try makeTempHome()
    _ = try runReporter(args: ["codex", "Stop"], stdin: "{}", home: home)
    let names = try FileManager.default.contentsOfDirectory(atPath: MyNotchPaths(home: home).inbox.path)
    #expect(names.allSatisfy { !$0.hasPrefix(".tmp-") })
}
```

`inboxFiles` mengembalikan file `.json` di inbox.

- [ ] **Step 7: Jalankan, pastikan gagal**

Run: `swift test --filter NotchReportScriptTests`
Expected: FAIL (`NotchReportScript` belum ada atau skrip tidak ditemukan).

- [ ] **Step 8: Tulis `notch-report.sh` dan `NotchReportScript`**

POSIX `sh`. Urutan: `umask 077`; validasi kedua argumen dengan `case` pola (tolak kosong, lebih dari 64 karakter, karakter di luar `[A-Za-z0-9_-]`) lalu `exit 0`; `mkdir -p "$HOME/.mynotch/inbox"`; `payload=$(head -c 262144)`; kosong → `null`; tulis amplop ke `.tmp-<ts>-<pid>-<rand>` lalu `mv` ke `<ts>-<pid>-<rand>.json`; semua stderr ke `/dev/null`; diakhiri `exit 0`. `pid` = `$PPID`, `ts` = `date +%s`, `rand` = `$$` ditambah `od -An -N4 -tu4 /dev/urandom`.

- [ ] **Step 9: Jalankan, pastikan lulus**

Run: `swift test`
Expected: semua test PASS.

- [ ] **Step 10: Commit**

```bash
git add AgentMonitorKit
git commit -m "feat(agents): add AgentMonitorKit with inbox envelope and notch-report script"
```

---

### Task 2: Rekam payload hooks asli sebagai fixture

**Files:**
- Create: `AgentMonitorKit/Tests/AgentMonitorKitTests/Fixtures/claude-code/<Event>.json` (satu per event yang terekam)
- Create: `AgentMonitorKit/Tests/AgentMonitorKitTests/Fixtures/codex/<Event>.json`
- Create: `AgentMonitorKit/Tests/AgentMonitorKitTests/FixtureTests.swift`
- Modify: `docs/superpowers/specs/2026-11-25-agent-monitor-design.md` (tabel 5.2 dan daftar event 5.9 bila hasil rekaman berbeda)

**Interfaces:**
- Consumes: `NotchReportScript.url`, `InboxEvent.decode` (Task 1).
- Produces: `func fixture(_ agent: String, _ event: String) throws -> InboxEvent` di `FixtureTests.swift` (helper test, dipakai Task 3).

Rekaman dilakukan di folder sementara dengan konfigurasi hooks tingkat proyek, sehingga `~/.claude/settings.json` dan `~/.codex/hooks.json` tidak disentuh.

- [ ] **Step 1: Siapkan folder rekaman**

`mkdir -p "$SCRATCH/capture/.claude" "$SCRATCH/capture/.codex"`. Pasang skrip: `install -m 700 AgentMonitorKit/Sources/AgentMonitorKit/Resources/notch-report.sh ~/.mynotch/bin/notch-report` (mode folder `0700`). Tulis `capture/.claude/settings.local.json` dan `capture/.codex/hooks.json` dengan format:

```json
{"hooks": {"<Event>": [{"matcher": ".*", "hooks": [{"type": "command", "command": "~/.mynotch/bin/notch-report <agent> <Event>", "timeout": 5}]}]}}
```

Event Claude Code: `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Notification`, `Stop`, `SubagentStart`, `SubagentStop`, `StopFailure`, `SessionEnd`. Event Codex: `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `PostToolUse`, `Stop`, `SubagentStop`.

- [ ] **Step 2: Rekam Claude Code (interaktif)**

Di Terminal, `cd "$SCRATCH/capture" && claude`. Minta: "jalankan `ls` lalu pakai subagent Explore untuk membaca README" (memicu izin, PostToolUse, subagent). Setujui izin, tunggu selesai, ketik `/exit`.
Expected: `ls ~/.mynotch/inbox` berisi file untuk setidaknya `SessionStart`, `UserPromptSubmit`, `Notification`, `PostToolUse`, `Stop`, `SubagentStop`, `SessionEnd`. Catat event yang tidak muncul (`SubagentStart`, `StopFailure`).

- [ ] **Step 3: Rekam Codex (interaktif)**

`cd "$SCRATCH/capture" && codex`, minta perintah shell yang butuh izin, setujui, keluar. Bila Codex meminta persetujuan hooks proyek, setujui di dalam Codex.
Expected: file inbox untuk `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `PostToolUse`, `Stop`.

- [ ] **Step 4: Samarkan dan simpan fixture**

Untuk tiap file: ganti `/Users/mac` dengan `/Users/test`; kosongkan nilai `prompt`, `tool_input`, `tool_response`, `transcript_path`, `last_assistant_message` menjadi `"<redacted>"`; simpan per event ke folder fixture. Kosongkan `~/.mynotch/inbox`. Hapus folder rekaman.

- [ ] **Step 5: Test bahwa semua fixture ter-decode**

```swift
@Test(arguments: fixtureFiles())
func fixtureDecodes(url: URL) throws {
    let event = try InboxEvent.decode(Data(contentsOf: url))
    #expect(event.payload["session_id"]?.stringValue?.isEmpty == false)
}
```

Run: `swift test --filter FixtureTests`
Expected: PASS untuk semua fixture.

- [ ] **Step 6: Selaraskan spec dengan rekaman**

Bila nama event atau field berbeda dari tabel 5.2 (misalnya `message` tidak ada di `Notification` Codex, atau `StopFailure`/`SubagentStart` tidak terekam), perbarui tabel 5.2 dan daftar event 5.9 sesuai rekaman. Event yang tidak terekam dihapus dari daftar pasang.

- [ ] **Step 7: Commit**

```bash
git add AgentMonitorKit/Tests docs/superpowers/specs/2026-11-25-agent-monitor-design.md
git commit -m "test(agents): add recorded Claude Code and Codex hook fixtures"
```

---

### Task 3: Model dan `ClaudeFormatAdapter`

**Files:**
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/Models.swift`
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/ClaudeFormatAdapter.swift`
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/TextTruncation.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/ClaudeFormatAdapterTests.swift`

**Interfaces:**
- Consumes: `InboxEvent`, `JSONValue` (Task 1); `fixture(_:_:)` (Task 2).
- Produces:
  - `public enum AgentStatus: String, Sendable, Codable, CaseIterable { case waiting, error, running, done }` dengan `var sortRank: Int` (waiting 0, error 1, running 2, done 3)
  - `public enum SessionOrigin: Sendable, Equatable { case hooks, process }`
  - `public struct AgentSession: Sendable, Equatable, Identifiable { let id: String; let agentID: String; let pid: Int32; let cwdName: String?; let status: AgentStatus; let detail: String?; let subagentCount: Int; let startedAt: Date; let updatedAt: Date; let origin: SessionOrigin }`
  - `public enum AgentEventKind: Sendable, Equatable { case status(AgentStatus, detail: String?), subagentStarted, subagentStopped, sessionEnded }`
  - `public struct AgentEvent: Sendable, Equatable { let sessionID: String; let agentID: String; let pid: Int32; let cwdName: String?; let kind: AgentEventKind; let at: Date }`
  - `public enum ClaudeFormatAdapter { public static func adapt(_ event: InboxEvent) -> AgentEvent? }` (nil = event diabaikan)
  - `public enum TextTruncation { public static func detail(_ text: String, limit: Int = 80) -> String }`

- [ ] **Step 1: Tulis test yang gagal**

```swift
@Test func notificationBecomesWaitingWithMessage() throws {
    let e = try #require(ClaudeFormatAdapter.adapt(fixture("claude-code", "Notification")))
    guard case .status(.waiting, let detail) = e.kind else { Issue.record("bukan waiting"); return }
    #expect(detail?.isEmpty == false)
    #expect(e.agentID == "claude-code")
}

@Test func codexPermissionRequestBecomesWaiting() throws {
    let e = try #require(ClaudeFormatAdapter.adapt(fixture("codex", "PermissionRequest")))
    guard case .status(.waiting, let detail) = e.kind else { Issue.record("bukan waiting"); return }
    #expect(detail?.hasPrefix("Izinkan ") == true)
}

@Test(arguments: ["SessionStart", "UserPromptSubmit", "PostToolUse"])
func runningEvents(name: String) throws {
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", name))?.kind == .status(.running, detail: nil))
}

@Test func stopBecomesDone() throws {
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", "Stop"))?.kind == .status(.done, detail: nil))
}

@Test func sessionEndEndsSession() throws {
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", "SessionEnd"))?.kind == .sessionEnded)
}

@Test func cwdNameIsLastPathComponent() throws {
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", "Stop"))?.cwdName == URL(fileURLWithPath: fixture("claude-code", "Stop").payload["cwd"]!.stringValue!).lastPathComponent)
}

@Test func unknownEventIgnored() {
    let e = InboxEvent(version: 1, source: "claude-code", event: "PreCompact", pid: 1, timestamp: .now, payload: .object(["session_id": .string("s")]))
    #expect(ClaudeFormatAdapter.adapt(e) == nil)
}

@Test func missingSessionIdFallsBackToSourceAndPid() {
    let e = InboxEvent(version: 1, source: "codex", event: "Stop", pid: 77, timestamp: .now, payload: .null)
    #expect(ClaudeFormatAdapter.adapt(e)?.sessionID == "codex-77")
}

@Test func detailCollapsesNewlinesAndTruncatesGraphemes() {
    let text = "Izinkan\nBash:\n" + String(repeating: "👩‍💻", count: 100)
    let out = TextTruncation.detail(text)
    #expect(!out.contains("\n"))
    #expect(out.count == 80)
    #expect(out.hasSuffix("…"))
}
```

Tambahkan test `subagentStopDecrements`/`subagentStart` hanya untuk event yang ada fixture-nya (Task 2).

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `swift test --filter ClaudeFormatAdapterTests`
Expected: FAIL kompilasi (`ClaudeFormatAdapter` tidak ada).

- [ ] **Step 3: Implementasi**

Pemetaan event mengikuti tabel 5.2 spec (versi setelah Task 2). `agentID = event.source`. Detail `waiting`: `message` bila ada; untuk `PermissionRequest`, `"Izinkan \(tool_name)?"`; keduanya lewat `TextTruncation.detail`. `TextTruncation.detail`: ganti `\n`/`\r` dengan spasi, rapatkan spasi ganda, lalu bila lebih dari `limit` karakter (Character = grapheme), ambil `limit - 1` karakter dan tambahkan `…`. Field `prompt`, `tool_input`, `tool_response` tidak dibaca.

- [ ] **Step 4: Jalankan, pastikan lulus**

Run: `swift test`
Expected: semua PASS.

- [ ] **Step 5: Commit**

```bash
git add AgentMonitorKit
git commit -m "feat(agents): map Claude-format hook events to agent events"
```

---

### Task 4: `AgentState` reducer

**Files:**
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/AgentState.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/AgentStateTests.swift`

**Interfaces:**
- Consumes: `AgentSession`, `AgentEvent`, `AgentStatus` (Task 3); `ScannedProcess` (Task 6; tulis tipe `ScannedProcess` di task ini bila Task 6 belum ada: `public struct ScannedProcess: Sendable, Equatable { let pid: Int32; let agentID: String; let startedAt: Date }`).
- Produces:
  - `public struct StatusChange: Sendable, Equatable { let session: AgentSession; let from: AgentStatus?; let to: AgentStatus }`
  - `public struct AgentState: Sendable, Equatable { public let sessions: [String: AgentSession]; public init(sessions: [String: AgentSession] = [:]) }`
  - `func reducing(_ event: AgentEvent) -> (state: AgentState, changes: [StatusChange])`
  - `func merging(scanned: [ScannedProcess], now: Date) -> AgentState`
  - `func pruning(isAlive: (Int32) -> Bool) -> AgentState`
  - `var sortedSessions: [AgentSession]`

- [ ] **Step 1: Tulis test yang gagal**

Helper `ev(_ session: String, _ kind: AgentEventKind, pid: Int32 = 10, at: TimeInterval = 0)`.

```swift
@Test func startCreatesRunningSession() {
    let (s, changes) = AgentState().reducing(ev("a", .status(.running, detail: nil)))
    #expect(s.sessions["a"]?.status == .running)
    #expect(s.sessions["a"]?.origin == .hooks)
    #expect(changes == [StatusChange(session: s.sessions["a"]!, from: nil, to: .running)])
}

@Test func unknownSessionCreatedFromAnyStatusEvent() {
    let (s, _) = AgentState().reducing(ev("late", .status(.waiting, detail: "Izinkan Bash?")))
    #expect(s.sessions["late"]?.status == .waiting)
    #expect(s.sessions["late"]?.detail == "Izinkan Bash?")
}

@Test func sameStatusProducesNoChange() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil))).state
    #expect(s1.reducing(ev("a", .status(.running, detail: nil), at: 5)).changes.isEmpty)
}

@Test func waitingClearedByRunning() {
    let s1 = AgentState().reducing(ev("a", .status(.waiting, detail: "x"))).state
    let (s2, changes) = s1.reducing(ev("a", .status(.running, detail: nil), at: 1))
    #expect(s2.sessions["a"]?.status == .running)
    #expect(s2.sessions["a"]?.detail == nil)
    #expect(changes.first?.from == .waiting)
}

@Test func startedAtKeptAcrossUpdates() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil), at: 0)).state
    let s2 = s1.reducing(ev("a", .status(.done, detail: nil), at: 60)).state
    #expect(s2.sessions["a"]?.startedAt == Date(timeIntervalSince1970: 0))
    #expect(s2.sessions["a"]?.updatedAt == Date(timeIntervalSince1970: 60))
}

@Test func sessionEndedRemoves() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil))).state
    #expect(s1.reducing(ev("a", .sessionEnded)).state.sessions["a"] == nil)
}

@Test func subagentCountNeverNegative() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil))).state
    #expect(s1.reducing(ev("a", .subagentStopped)).state.sessions["a"]?.subagentCount == 0)
}

@Test func twoSessionsSameCwdStaySeparate() {
    let s = AgentState()
        .reducing(ev("a", .status(.running, detail: nil), pid: 10)).state
        .reducing(ev("b", .status(.waiting, detail: nil), pid: 11)).state
    #expect(s.sessions.count == 2)
}

@Test func scanAddsProcessOnlySession() {
    let s = AgentState().merging(scanned: [ScannedProcess(pid: 99, agentID: "aider", startedAt: .distantPast)], now: .now)
    #expect(s.sessions.values.first?.origin == .process)
    #expect(s.sessions.values.first?.status == .running)
}

@Test func scanSkipsPidOwnedByHooksSession() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil), pid: 50)).state
    #expect(s1.merging(scanned: [ScannedProcess(pid: 50, agentID: "claude-code", startedAt: .distantPast)], now: .now).sessions.count == 1)
}

@Test func scanRemovesVanishedProcessSessionsOnly() {
    let s1 = AgentState()
        .reducing(ev("a", .status(.running, detail: nil), pid: 50)).state
        .merging(scanned: [ScannedProcess(pid: 99, agentID: "aider", startedAt: .distantPast)], now: .now)
    let s2 = s1.merging(scanned: [], now: .now)
    #expect(s2.sessions.count == 1)
    #expect(s2.sessions["a"] != nil)
}

@Test func pruneRemovesDeadPids() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil), pid: 50)).state
    #expect(s1.pruning(isAlive: { _ in false }).sessions.isEmpty)
}

@Test func sortOrderByStatusThenRecency() {
    let s = AgentState()
        .reducing(ev("done", .status(.done, detail: nil), at: 9)).state
        .reducing(ev("run1", .status(.running, detail: nil), at: 1)).state
        .reducing(ev("run2", .status(.running, detail: nil), at: 2)).state
        .reducing(ev("wait", .status(.waiting, detail: nil), at: 0)).state
    #expect(s.sortedSessions.map(\.id) == ["wait", "run2", "run1", "done"])
}
```

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `swift test --filter AgentStateTests`
Expected: FAIL kompilasi.

- [ ] **Step 3: Implementasi**

ID sesi `.process` = `"proc-\(pid)"`. `merging` menambah sesi `.process` untuk proses yang PID-nya tidak dimiliki sesi mana pun, dan menghapus sesi `.process` yang PID-nya tidak ada di hasil scan. `pruning` menghapus semua sesi (hooks maupun process) yang `isAlive(pid)` false. Event status dengan detail nil menghapus detail lama.

- [ ] **Step 4: Jalankan, pastikan lulus**

Run: `swift test`
Expected: semua PASS.

- [ ] **Step 5: Commit**

```bash
git add AgentMonitorKit
git commit -m "feat(agents): add immutable agent state reducer"
```

---

### Task 5: `NotificationPolicy` dan `NoticeQueue`

**Files:**
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/NotificationPolicy.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/NotificationPolicyTests.swift`

**Interfaces:**
- Consumes: `StatusChange`, `AgentSession`, `AgentStatus` (Task 3–4).
- Produces:
  - `public struct NotifySettings: Sendable, Equatable { let waiting: Bool; let error: Bool; let done: Bool }`
  - `public struct NoticeContext: Sendable, Equatable { let frontmostBundleID: String?; let hostBundleID: String?; let notchOpen: Bool; let hiddenForFullscreen: Bool }`
  - `public struct AgentNotice: Sendable, Equatable, Identifiable { let id: String /* sessionID */; let agentID: String; let title: String; let status: AgentStatus; let duration: TimeInterval }`
  - `public enum NotificationPolicy { public static func notice(for change: StatusChange, displayName: String, settings: NotifySettings, context: NoticeContext) -> AgentNotice? }`
  - `public struct NoticeQueue: Sendable, Equatable { public let pending: [AgentNotice]; public init(pending: [AgentNotice] = []); func enqueuing(_ notice: AgentNotice) -> NoticeQueue; func dequeued() -> (notice: AgentNotice?, queue: NoticeQueue) }`

- [ ] **Step 1: Tulis test yang gagal**

```swift
let all = NotifySettings(waiting: true, error: true, done: true)
let calm = NoticeContext(frontmostBundleID: "com.apple.Safari", hostBundleID: "com.anthropic.claudefordesktop", notchOpen: false, hiddenForFullscreen: false)

@Test func waitingShowsFiveSeconds() {
    let n = NotificationPolicy.notice(for: change(to: .waiting, cwd: "mynotch"), displayName: "Claude Code", settings: all, context: calm)
    #expect(n?.duration == 5)
    #expect(n?.title == "Claude Code · mynotch")
}

@Test(arguments: [AgentStatus.error, .done])
func errorAndDoneShowThreeSeconds(status: AgentStatus) {
    #expect(NotificationPolicy.notice(for: change(to: status), displayName: "Codex", settings: all, context: calm)?.duration == 3)
}

@Test func runningNeverNotifies() {
    #expect(NotificationPolicy.notice(for: change(to: .running), displayName: "x", settings: all, context: calm) == nil)
}

@Test func titleWithoutCwdIsDisplayNameOnly() {
    #expect(NotificationPolicy.notice(for: change(to: .done, cwd: nil), displayName: "aider", settings: all, context: calm)?.title == "aider")
}

@Test func suppressedWhenHostFrontmost() {
    let ctx = NoticeContext(frontmostBundleID: "com.anthropic.claudefordesktop", hostBundleID: "com.anthropic.claudefordesktop", notchOpen: false, hiddenForFullscreen: false)
    #expect(NotificationPolicy.notice(for: change(to: .waiting), displayName: "x", settings: all, context: ctx) == nil)
}

@Test func suppressedWhenNotchOpenOrFullscreen() {
    let open = NoticeContext(frontmostBundleID: nil, hostBundleID: nil, notchOpen: true, hiddenForFullscreen: false)
    let full = NoticeContext(frontmostBundleID: nil, hostBundleID: nil, notchOpen: false, hiddenForFullscreen: true)
    #expect(NotificationPolicy.notice(for: change(to: .waiting), displayName: "x", settings: all, context: open) == nil)
    #expect(NotificationPolicy.notice(for: change(to: .waiting), displayName: "x", settings: all, context: full) == nil)
}

@Test func respectsPerStatusSetting() {
    let noDone = NotifySettings(waiting: true, error: true, done: false)
    #expect(NotificationPolicy.notice(for: change(to: .done), displayName: "x", settings: noDone, context: calm) == nil)
}

@Test func queueReplacesPendingFromSameSession() {
    let q = NoticeQueue().enqueuing(notice("a", .running)).enqueuing(notice("b", .done)).enqueuing(notice("a", .waiting))
    #expect(q.pending.map(\.id) == ["a", "b"])
    #expect(q.pending.first?.status == .waiting)
}

@Test func dequeueIsFifo() {
    let (first, rest) = NoticeQueue().enqueuing(notice("a", .done)).enqueuing(notice("b", .done)).dequeued()
    #expect(first?.id == "a")
    #expect(rest.pending.map(\.id) == ["b"])
}
```

`change(to:cwd:)` dan `notice(_:_:)` adalah helper test yang membuat `StatusChange`/`AgentNotice` minimal.

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `swift test --filter NotificationPolicyTests`
Expected: FAIL kompilasi.

- [ ] **Step 3: Implementasi**

Penekanan "host frontmost" hanya berlaku bila `hostBundleID` tidak nil dan sama dengan `frontmostBundleID`.

- [ ] **Step 4: Jalankan, pastikan lulus**

Run: `swift test`
Expected: semua PASS.

- [ ] **Step 5: Commit**

```bash
git add AgentMonitorKit
git commit -m "feat(agents): add notification policy and notice queue"
```

---

### Task 6: Registry dan `ProcessMatcher`

**Files:**
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/AgentRegistry.swift`
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/ProcessMatcher.swift`
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/Resources/agents.json`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/ProcessMatcherTests.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/AgentRegistryTests.swift`

**Interfaces:**
- Consumes: `ScannedProcess` (dari Task 4).
- Produces:
  - `public struct MatchRule: Sendable, Codable, Equatable { let executable: [String]; let argvContains: [String] }`
  - `public struct HookSpec: Sendable, Codable, Equatable { let format: String; let config: String; let events: [String] }`
  - `public struct AgentDefinition: Sendable, Codable, Equatable, Identifiable { let id: String; let displayName: String; let match: MatchRule; let appBundleIDs: [String]; let hooks: HookSpec? }`
  - `public struct CustomAgentRule: Sendable, Codable, Equatable { let id: String; let displayName: String; let executable: String }` dengan `var definition: AgentDefinition`
  - `public struct AgentRegistry: Sendable { public let definitions: [AgentDefinition]; public static func bundled() throws -> AgentRegistry; func adding(_ custom: [CustomAgentRule]) -> AgentRegistry; func definition(id: String) -> AgentDefinition? }`
  - `public struct ProcessSnapshot: Sendable, Equatable { let pid: Int32; let ppid: Int32; let executable: String; let arguments: [String]; let startedAt: Date }`
  - `public enum ProcessMatcher { static let interpreters: Set<String>; static func agentID(for p: ProcessSnapshot, in r: AgentRegistry) -> String?; static func scan(_ ps: [ProcessSnapshot], in r: AgentRegistry) -> [ScannedProcess]; static func ancestors(of pid: Int32, lookup: (Int32) -> ProcessSnapshot?, maxDepth: Int = 16) -> [ProcessSnapshot]; static func resolveAgentPID(from pid: Int32, agentID: String, lookup: (Int32) -> ProcessSnapshot?, in r: AgentRegistry) -> Int32 }`

- [ ] **Step 1: Tulis `agents.json`**

Isi tabel 5.7 spec persis (11 entri). Entri `claude-code` dan `codex` memakai `hooks.events` sesuai daftar 5.9 spec (versi setelah Task 2), `config` berupa path dengan `~`. Entri lain `"hooks": null`.

- [ ] **Step 2: Tulis test yang gagal**

```swift
let reg = try! AgentRegistry.bundled()
func snap(_ pid: Int32, _ exe: String, _ args: [String] = [], ppid: Int32 = 1) -> ProcessSnapshot {
    ProcessSnapshot(pid: pid, ppid: ppid, executable: exe, arguments: args, startedAt: .distantPast)
}

@Test func bundledRegistryHasElevenAgents() { #expect(reg.definitions.count == 11) }
@Test func exactExecutableMatches() { #expect(ProcessMatcher.agentID(for: snap(1, "claude"), in: reg) == "claude-code") }
@Test func matchIsCaseSensitive() { #expect(ProcessMatcher.agentID(for: snap(1, "Claude"), in: reg) == nil) }
@Test func interpreterMatchesByArgumentBasename() {
    #expect(ProcessMatcher.agentID(for: snap(1, "node", ["node", "/opt/homebrew/bin/gemini"]), in: reg) == "gemini-cli")
}
@Test func nonInterpreterIgnoresArguments() {
    #expect(ProcessMatcher.agentID(for: snap(1, "vim", ["vim", "gemini"]), in: reg) == nil)
}
@Test func customRuleMatches() {
    let r = reg.adding([CustomAgentRule(id: "myagent", displayName: "myagent", executable: "myagent")])
    #expect(ProcessMatcher.agentID(for: snap(1, "myagent"), in: r) == "myagent")
}
@Test func ancestorsStopAtMaxDepth() {
    let lookup: (Int32) -> ProcessSnapshot? = { pid in snap(pid, "sh", ppid: pid + 1) }
    #expect(ProcessMatcher.ancestors(of: 1, lookup: lookup).count == 16)
}
@Test func resolveAgentPidWalksPastShell() {
    let table = [100: snap(100, "sh", ppid: 50), 50: snap(50, "claude", ppid: 10), 10: snap(10, "disclaimer", ppid: 1)]
    #expect(ProcessMatcher.resolveAgentPID(from: 100, agentID: "claude-code", lookup: { table[Int($0)] }, in: reg) == 50)
}
@Test func resolveFallsBackToOriginalPid() {
    #expect(ProcessMatcher.resolveAgentPID(from: 100, agentID: "claude-code", lookup: { _ in nil }, in: reg) == 100)
}
```

- [ ] **Step 3: Jalankan, pastikan gagal**

Run: `swift test --filter "ProcessMatcherTests|AgentRegistryTests"`
Expected: FAIL kompilasi.

- [ ] **Step 4: Implementasi**

`interpreters = ["node", "bun", "python3", "python"]`. Untuk interpreter, cocokkan `URL(fileURLWithPath:).lastPathComponent` dari `arguments.dropFirst()` dengan `argvContains`. `ancestors` dimulai dari proses `pid` itu sendiri, berhenti di `ppid <= 1`, lookup nil, atau `maxDepth`. `resolveAgentPID` mengembalikan PID leluhur pertama yang `agentID(for:)`-nya sama, atau `pid` asli. `bundled()` membaca `Bundle.module.url(forResource: "agents", withExtension: "json", subdirectory: "Resources")`.

- [ ] **Step 5: Jalankan, pastikan lulus**

Run: `swift test`
Expected: semua PASS.

- [ ] **Step 6: Commit**

```bash
git add AgentMonitorKit
git commit -m "feat(agents): add agent registry and process matcher"
```

---

### Task 7: `HookConfigMerger`

**Files:**
- Create: `AgentMonitorKit/Sources/AgentMonitorKit/HookConfigMerger.swift`
- Test: `AgentMonitorKit/Tests/AgentMonitorKitTests/HookConfigMergerTests.swift`

**Interfaces:**
- Consumes: `JSONValue` (Task 1).
- Produces:
  - `public enum HookConfigMerger { public static let marker = "/.mynotch/bin/notch-report"; static func installing(into config: JSONValue, agentID: String, events: [String], reporterPath: String) -> JSONValue; static func uninstalling(from config: JSONValue) -> JSONValue; static func isInstalled(in config: JSONValue, events: [String]) -> Bool }`

- [ ] **Step 1: Tulis test yang gagal**

Grup yang ditambahkan per event: `{"matcher": ".*", "hooks": [{"type": "command", "command": "<reporterPath> <agentID> <Event>", "timeout": 5}]}`.

```swift
let path = "~/.mynotch/bin/notch-report"

@Test func installIntoEmptyObject() {
    let out = HookConfigMerger.installing(into: .object([:]), agentID: "codex", events: ["Stop"], reporterPath: path)
    #expect(out["hooks"]?["Stop"]?.arrayCount == 1)
    #expect(HookConfigMerger.isInstalled(in: out, events: ["Stop"]))
}

@Test func installPreservesForeignHooks() throws {
    let existing = try decodeJSON(#"{"model":"x","hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"other"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[]}]}}"#)
    let out = HookConfigMerger.installing(into: existing, agentID: "codex", events: ["Stop"], reporterPath: path)
    #expect(out["model"] == .string("x"))
    #expect(out["hooks"]?["Stop"]?.arrayCount == 2)
    #expect(out["hooks"]?["PreToolUse"] == existing["hooks"]?["PreToolUse"])
}

@Test func installIsIdempotent() {
    let once = HookConfigMerger.installing(into: .object([:]), agentID: "codex", events: ["Stop"], reporterPath: path)
    #expect(HookConfigMerger.installing(into: once, agentID: "codex", events: ["Stop"], reporterPath: path) == once)
}

@Test func uninstallRemovesOnlyOwnEntries() throws {
    let existing = try decodeJSON(#"{"hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"other"}]}]}}"#)
    let installed = HookConfigMerger.installing(into: existing, agentID: "codex", events: ["Stop", "SessionStart"], reporterPath: path)
    #expect(HookConfigMerger.uninstalling(from: installed) == existing)
}

@Test func partialInstallIsNotInstalled() {
    let out = HookConfigMerger.installing(into: .object([:]), agentID: "codex", events: ["Stop"], reporterPath: path)
    #expect(!HookConfigMerger.isInstalled(in: out, events: ["Stop", "SessionStart"]))
}
```

`arrayCount` adalah extension test pada `JSONValue?`. `decodeJSON` men-decode string ke `JSONValue`.

- [ ] **Step 2: Jalankan, pastikan gagal**

Run: `swift test --filter HookConfigMergerTests`
Expected: FAIL kompilasi.

- [ ] **Step 3: Implementasi**

Sebuah grup dianggap milik notch bila salah satu `hooks[].command` mengandung `marker`. `uninstalling` menghapus grup milik notch, lalu menghapus array event yang menjadi kosong, lalu menghapus key `hooks` bila objeknya menjadi kosong.

- [ ] **Step 4: Jalankan, pastikan lulus**

Run: `swift test`
Expected: semua PASS.

- [ ] **Step 5: Ukur cakupan**

Run: `swift test --enable-code-coverage && xcrun llvm-cov report .build/debug/AgentMonitorKitPackageTests.xctest/Contents/MacOS/AgentMonitorKitPackageTests -instr-profile .build/debug/codecov/default.profdata -ignore-filename-regex "Tests/"`
Expected: total baris ≥ 80%. Bila kurang, tambahkan test untuk cabang yang belum tercakup sebelum commit.

- [ ] **Step 6: Commit**

```bash
git add AgentMonitorKit
git commit -m "feat(agents): add hook config merger"
```

---

### Task 8: Lapis app — watcher, scanner, resolver, manager

**Files:**
- Modify: `boringNotch.xcodeproj/project.pbxproj` (tambah paket lokal `AgentMonitorKit`, link ke target `boringNotch`; tambah folder `boringNotch/managers/AgentMonitor` dan `boringNotch/components/Agents` sebagai folder tersinkron)
- Create: `boringNotch/managers/AgentMonitor/InboxWatcher.swift`
- Create: `boringNotch/managers/AgentMonitor/ProcessScanner.swift`
- Create: `boringNotch/managers/AgentMonitor/HostAppResolver.swift`
- Create: `boringNotch/managers/AgentMonitor/AgentMonitorManager.swift`
- Modify: `boringNotch/models/Constants.swift` (key Defaults)
- Modify: `boringNotch/boringNotchApp.swift` (`applicationDidFinishLaunching`, `applicationWillTerminate`)

**Interfaces:**
- Consumes: semua tipe publik `AgentMonitorKit` (Task 1–7).
- Produces:
  - `final class InboxWatcher { init(directory: URL, maxAge: TimeInterval = 600, onEvents: @escaping @MainActor ([InboxEvent]) -> Void); func start(); func stop() }`
  - `enum ProcessScanner { static func snapshotAll() -> [ProcessSnapshot]; static func snapshot(pid: Int32) -> ProcessSnapshot?; static func isAlive(_ pid: Int32) -> Bool }`
  - `@MainActor final class HostAppResolver { func hostApp(forAgentPID pid: Int32) -> NSRunningApplication?; func forget(pid: Int32) }`
  - `@MainActor final class AgentMonitorManager: ObservableObject { static let shared; @Published private(set) var sessions: [AgentSession]; var registry: AgentRegistry { get }; var notchContextProvider: (() -> (notchOpen: Bool, hiddenForFullscreen: Bool))?; func start(); func stop(); func activateHost(of session: AgentSession); func displayName(for agentID: String) -> String; var onNotice: ((AgentNotice) -> Void)? }`
  - Defaults keys: `agentMonitorEnabled`, `agentNotifyWaiting`, `agentNotifyError`, `agentNotifyDone`, `agentCustomRules: [CustomAgentRule]` (`CustomAgentRule` dibuat `Defaults.Serializable` lewat extension di `Constants.swift`).

- [ ] **Step 1: Tambah paket dan folder di Xcode**

File > Add Package Dependencies > Add Local… → `AgentMonitorKit`, link product ke target `boringNotch`. Tambah kedua folder lewat File > Add Files… dengan opsi "Create folders" (folder tersinkron).
Verify: `xcodebuild … build` → `** BUILD SUCCEEDED **` dengan `import AgentMonitorKit` di satu file kosong.

- [ ] **Step 2: Implementasi `ProcessScanner`**

`proc_listallpids` → untuk tiap PID: `proc_pidinfo(PROC_PIDTBSDINFO)` untuk `pbi_uid` (lewati bila bukan `getuid()`), `pbi_ppid`, `pbi_start_tvsec`, `pbi_comm`; argumen dari `sysctl([CTL_KERN, KERN_PROCARGS2, pid])` (format: argc Int32, path executable, padding NUL, lalu argv). `executable` = basename path executable. `isAlive(pid)` = `kill(pid, 0) == 0 || errno == EPERM`.

- [ ] **Step 3: Implementasi `InboxWatcher`**

Buat folder dengan izin `0700` bila belum ada. `DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(dir, O_EVTONLY), eventMask: [.write, .delete, .rename])` di queue utilitas; saat event dan saat `start()`, baca semua entri. Untuk tiap entri: lewati nama berawalan `.tmp-` atau tidak berakhiran `.json`; `lstat` → harus `S_IFREG`, `st_uid == getuid()`, `st_size <= 300_000`; decode; buang bila `timestamp` lebih tua dari `maxAge`; hapus file dalam semua kasus; log kegagalan. Bila folder terhapus (`.delete`/`.rename` pada fd folder), buat ulang dan pasang ulang source. Event dikirim ke main actor dalam satu batch, diurutkan menurut `timestamp`.

- [ ] **Step 4: Implementasi `HostAppResolver`**

`ProcessMatcher.ancestors(of:lookup: ProcessScanner.snapshot)` lalu PID pertama yang `NSRunningApplication(processIdentifier:)` punya `bundleIdentifier`. Cache per PID agent.

- [ ] **Step 5: Implementasi `AgentMonitorManager`**

State: `AgentState`, `NoticeQueue`, `registry = bundled().adding(Defaults[.agentCustomRules])`. `start()`: bila `agentMonitorEnabled` false, tidak melakukan apa pun; jika true, nyalakan watcher dan timer scan 5 detik (scan di background, merge di main). Event inbox: `ClaudeFormatAdapter.adapt` → ganti `pid` dengan `ProcessMatcher.resolveAgentPID(from:agentID:lookup:in:)` → `reducing` → untuk tiap `StatusChange` panggil `NotificationPolicy.notice(…)` dengan `NoticeContext` dari `NSWorkspace.shared.frontmostApplication`, host resolver, dan `notchContextProvider?() ?? (false, false)` (dicek ulang juga sebelum menampilkan item dari antrean) → `enqueuing`. Antrean dijalankan satu per satu: `onNotice?(notice)`, tunggu `notice.duration + 0.4` detik, ambil berikutnya. Setiap tick scan juga memanggil `pruning(isAlive:)` dan `resolver.forget` untuk PID yang hilang. `sessions = state.sortedSessions` setelah setiap perubahan. Observasi `Defaults.publisher(.agentMonitorEnabled)` untuk start/stop (dan reset `BoringViewCoordinator.shared.currentView = .home` bila dimatikan saat tab `.agents` aktif) serta `.agentCustomRules` untuk membangun ulang registry. Setiap perubahan status dicatat di log level `.debug`.

- [ ] **Step 6: Sambungkan ke app**

`applicationDidFinishLaunching`: pasang `AgentMonitorManager.shared.notchContextProvider` yang membaca `viewModels.values` bila `Defaults[.showOnAllDisplays]` aktif (`notchOpen`: `contains { $0.notchState == .open }`; `hiddenForFullscreen`: `!viewModels.isEmpty && viewModels.values.allSatisfy(\.hideOnClosed)`), atau membaca `self.vm` pada mode satu layar; lalu panggil `AgentMonitorManager.shared.start()`. `applicationWillTerminate`: `stop()`.

- [ ] **Step 7: Build dan verifikasi dengan log**

Run: `xcodebuild … build` → `** BUILD SUCCEEDED **`. Jalankan app, lalu di Terminal lain:
`log stream --level debug --predicate 'subsystem == "local.mynotch.boringnotch" AND category == "AgentMonitor"'`
Kirim event buatan: `echo '{"session_id":"t1","cwd":"/tmp/demo"}' | ~/.mynotch/bin/notch-report claude-code Notification`
Expected: log menampilkan sesi `t1` berstatus `waiting`; file inbox hilang. Dalam 5 detik log juga menampilkan sesi untuk proses `claude` dari sesi Claude Code yang sedang berjalan (origin `process` bila hooks belum terpasang). PID sesi `t1` adalah shell Terminal tempat perintah dijalankan (tidak ada leluhur yang cocok dengan agent, jadi PID asli dipakai), sehingga sesi `t1` tetap ada selama tab Terminal itu terbuka dan hilang dalam 5 detik setelah tab ditutup — ini perilaku yang diharapkan.

- [ ] **Step 8: Commit**

```bash
git add boringNotch.xcodeproj boringNotch/managers/AgentMonitor boringNotch/models/Constants.swift boringNotch/boringNotchApp.swift
git commit -m "feat(agents): watch inbox, scan processes, and track agent sessions"
```

---

### Task 9: Tab Agents dan logo

**Files:**
- Create: `boringNotch/managers/AgentMonitor/AgentIconProvider.swift`
- Create: `boringNotch/components/Agents/AgentsTabView.swift`
- Create: `boringNotch/components/Agents/AgentRowView.swift`
- Create: `boringNotch/components/Agents/AgentStatusStyle.swift`
- Modify: `boringNotch/enums/generic.swift` (`NotchViews.agents`)
- Modify: `boringNotch/components/Notch/BoringHeader.swift:19` (tampilkan `TabSelectionView` saat `Defaults[.agentMonitorEnabled]` aktif walau `boringShelf` mati)
- Modify: `boringNotch/components/Tabs/TabSelectionView.swift` (filter daftar tab dinamis berdasarkan `boringShelf` dan `agentMonitorEnabled`)
- Modify: `boringNotch/ContentView.swift:347-352` (`case .agents`)

**Interfaces:**
- Consumes: `AgentMonitorManager` (Task 8), `AgentRegistry`, `AgentDefinition`, `AgentSession`, `AgentStatus`.
- Produces:
  - `@MainActor final class AgentIconProvider: ObservableObject { static let shared; func icon(for agentID: String) -> NSImage?; func setCustomIcon(_ source: URL, for agentID: String) throws; func invalidate() }` (nil = pakai SF Symbol `sparkles`)
  - `extension AgentStatus { var color: Color; var label: String }` di `AgentStatusStyle.swift` (label: "Butuh input", "Error", "Berjalan", "Selesai"; warna sesuai Global Constraints)
  - `func formatElapsed(since: Date, now: Date) -> String` di `AgentStatusStyle.swift` ("<1 mnt", "4 mnt", "1 jam", "2 jam")

- [ ] **Step 1: `AgentIconProvider`**

Urutan: `~/.mynotch/icons/<id>.png` bila ada (`NSImage(contentsOf:)`), lalu `AppIconAsNSImage(for:)` untuk tiap `appBundleIDs`, lalu nil. Cache per `agentID`. `setCustomIcon` menyalin file (diubah ke PNG lewat `NSBitmapImageRep`) ke folder ikon dengan izin `0600`, lalu `invalidate()`. Pantau folder ikon dengan `DispatchSource` yang sama polanya dengan `InboxWatcher` untuk `invalidate()`.

- [ ] **Step 2: Baris dan tab**

`AgentRowView(session:)`: logo 22 pt; judul `displayName` + (" · " + `cwdName`); subjudul: `detail`, atau "Terdeteksi dari proses" untuk `.process`, atau `status.label`; tambahan " · N subagent" bila `subagentCount > 0`; kanan: titik `status.color` + `formatElapsed`. Seluruh baris adalah `Button` yang memanggil `activateHost(of:)`. `AgentsTabView`: `ScrollView` daftar `sessions`, header kecil "N agent", kosong → "Tidak ada agent yang berjalan". Waktu diperbarui dengan `TimelineView(.periodic(from: .now, by: 30))`.

- [ ] **Step 3: Daftarkan tab**

`NotchViews.agents`; di `TabSelectionView`, buat daftar tab dinamis (Home selalu ada, Shelf bila `Defaults[.boringShelf]`, `TabModel(label: "Agents", icon: "sparkles", view: .agents)` bila `Defaults[.agentMonitorEnabled]`) serta pantau perubahan `agentMonitorEnabled` agar bila dimatikan saat `coordinator.currentView == .agents` langsung di-reset ke `.home`; di `BoringHeader.swift:19`, tampilkan `TabSelectionView()` bila `((!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf]) || Defaults[.agentMonitorEnabled]`; `case .agents: AgentsTabView()` di `ContentView`.

- [ ] **Step 4: Build dan cek di app**

Run: `xcodebuild … build` → `** BUILD SUCCEEDED **`. Jalankan app; buka notch; pilih tab ✦.
Expected: sesi Claude Code yang sedang berjalan tampil dengan logo Claude.app; event buatan dari Task 8 Step 7 tampil sebagai baris amber dengan detailnya; klik baris Claude mengaktifkan app Claude.

- [ ] **Step 5: Commit**

```bash
git add boringNotch.xcodeproj boringNotch/managers/AgentMonitor boringNotch/components/Agents boringNotch/enums/generic.swift boringNotch/components/Notch/BoringHeader.swift boringNotch/components/Tabs/TabSelectionView.swift boringNotch/ContentView.swift
git commit -m "feat(agents): add agents tab with agent logos"
```

---

### Task 10: Notifikasi di notch tertutup

**Files:**
- Create: `boringNotch/components/Agents/AgentNoticeView.swift`
- Modify: `boringNotch/BoringViewCoordinator.swift` (`SneakContentType.agent`, `ExpandedItem.agent`, `toggleExpandingView`, durasi di `didSet`)
- Modify: `boringNotch/sizing/matters.swift` (`let agentNoticeWidth: CGFloat = 540`)
- Modify: `boringNotch/ContentView.swift:61-78` (`computedChinWidth`), `:259-287` (cabang notch tertutup), `:505-542` (`doOpen` dan `handleHover`)
- Modify: `boringNotch/managers/AgentMonitor/AgentMonitorManager.swift` (sambungkan `onNotice`)

**Interfaces:**
- Consumes: `AgentNotice` (Task 5), `AgentIconProvider` (Task 9), `AgentStatus.color`/`label` (Task 9).
- Produces:
  - `ExpandedItem.agent: AgentNotice?` (default nil)
  - `func toggleExpandingView(status: Bool, type: SneakContentType, value: CGFloat = 0, browser: BrowserType = .chromium, agent: AgentNotice? = nil)`

- [ ] **Step 1: Perluas coordinator**

Tambah `case agent` ke `SneakContentType` dan field `agent` ke `ExpandedItem`. Saat `toggleExpandingView(status: false, ...)` dipanggil, bersihkan `expandingView.agent = nil` supaya tidak ada state notice tersisa. Durasi di `expandingView.didSet`: `expandingView.agent?.duration ?? (type == .download ? 2 : 3)`.

- [ ] **Step 2: `AgentNoticeView(notice:)`**

`HStack`: sayap kiri (logo 16 pt + `notice.title`, font `.subheadline`, satu baris, terpotong di tengah), `Rectangle().fill(.black).frame(width: vm.closedNotchSize.width + 10)`, sayap kanan (titik `status.color` + `status.label`), tinggi `vm.effectiveClosedNotchHeight`; lebar total `agentNoticeWidth`. Mengikuti struktur cabang baterai di `ContentView.swift:260-286`.

- [ ] **Step 3: Sambungkan ke `ContentView`**

Cabang baru sebelum cabang `InlineHUD`: `coordinator.expandingView.show && coordinator.expandingView.type == .agent && vm.notchState == .closed && !vm.hideOnClosed`, dengan `if let notice = coordinator.expandingView.agent`. Di `computedChinWidth`, kondisi yang sama → `chinWidth = agentNoticeWidth`. Di `handleHover` dan `doOpen()` (untuk tap gesture): bila `coordinator.expandingView.show && coordinator.expandingView.type == .agent`, set `coordinator.currentView = .agents` dan langsung tutup notifikasi lewat `coordinator.toggleExpandingView(status: false, type: .agent)` sebelum membuka notch.

- [ ] **Step 4: Sambungkan manager**

Di `AgentMonitorManager.start()`, `onNotice = { BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .agent, agent: $0) }`. `NoticeContext` sudah membaca `notchOpen` dan `hiddenForFullscreen` lewat `notchContextProvider` yang dipasang oleh `AppDelegate` di Task 8.

- [ ] **Step 5: Build dan cek di app**

Run: `xcodebuild … build` → `** BUILD SUCCEEDED **`. Dengan app Finder di depan:
`echo '{"session_id":"t2","cwd":"/tmp/demo","message":"Claude needs your permission to use Bash"}' | ~/.mynotch/bin/notch-report claude-code Notification`
Expected: notch melebar ±5 detik dengan logo Claude, "Claude Code · demo", titik amber "Butuh input", lalu kembali. Kirim tiga event `Stop` untuk sesi berbeda berturut-turut → tampil bergantian. Putar musik lalu ulangi → notifikasi tampil, live activity musik kembali sesudahnya. Hover saat notifikasi tampil → notch terbuka di tab Agents.

- [ ] **Step 6: Commit**

```bash
git add boringNotch/components/Agents boringNotch/BoringViewCoordinator.swift boringNotch/sizing/matters.swift boringNotch/ContentView.swift boringNotch/managers/AgentMonitor
git commit -m "feat(agents): show agent notices in the closed notch"
```

---

### Task 11: Settings Agents dan pemasangan hooks

**Files:**
- Create: `boringNotch/managers/AgentMonitor/HookInstallerService.swift`
- Create: `boringNotch/components/Settings/AgentsSettingsView.swift`
- Modify: `boringNotch/components/Settings/SettingsView.swift:30-64` (NavigationLink "Agents") dan `:74-95` (`case "Agents"`)

**Interfaces:**
- Consumes: `HookConfigMerger`, `JSONValue`, `NotchReportScript.url`, `MyNotchPaths`, `AgentRegistry`, `CustomAgentRule`, `ProcessScanner.snapshotAll`, `AgentIconProvider.setCustomIcon`.
- Produces:
  - `enum HookInstallError: LocalizedError { case configMissing(String), invalidJSON(String), writeFailed(String) }`
  - `@MainActor final class HookInstallerService: ObservableObject { static let shared; @Published private(set) var installed: [String: Bool]; func refresh(); func install(_ def: AgentDefinition) throws(HookInstallError); func uninstall(_ def: AgentDefinition) throws(HookInstallError) }`

- [ ] **Step 1: `HookInstallerService`**

`install`: salin `NotchReportScript.url` ke `MyNotchPaths.reporter` dengan izin `0700` (folder `0700`); ekspansi `~` di `hooks.config`; file tidak ada → `configMissing`; buat cadangan `<file>.mynotch-backup-<yyyyMMdd-HHmmss>`; decode ke `JSONValue` (gagal → `invalidJSON`, file tidak disentuh); `HookConfigMerger.installing(… reporterPath: "~/.mynotch/bin/notch-report")`; encode `JSONEncoder` dengan `.prettyPrinted, .withoutEscapingSlashes`; decode ulang hasil encode sebagai validasi; tulis atomik (`Data.write(to:options: .atomic)`). `uninstall` sama tanpa penyalinan skrip. `refresh` mengisi `installed` lewat `isInstalled`.

- [ ] **Step 2: `AgentsSettingsView`**

Bagian: saklar `agentMonitorEnabled`; saklar tiga jenis notifikasi; daftar agent ber-hooks dengan status "Terpasang"/"Belum terpasang" dan tombol "Pasang hooks"/"Lepas hooks" (error ditampilkan sebagai teks merah di bawah baris); catatan untuk Codex: "Codex mungkin meminta persetujuan hook baru saat sesi berikutnya dimulai."; daftar `agentCustomRules` dengan tombol hapus dan tombol "Tambah dari proses yang berjalan" yang membuka sheet berisi proses milik user dari `ProcessScanner.snapshotAll()` (unik per `executable`, diurutkan, tanpa yang sudah cocok dengan registry); per agent (registry + custom), tombol "Pilih logo…" (`NSOpenPanel`, tipe gambar) yang memanggil `setCustomIcon`. Ikuti gaya `Form`/`Section` dari seksi Settings lain di `SettingsView.swift`.

- [ ] **Step 3: Daftarkan di Settings**

`NavigationLink(value: "Agents") { Label("Agents", systemImage: "sparkles") }` setelah "Shelf"; `case "Agents": AgentsSettingsView()`.

- [ ] **Step 4: Build dan cek di app**

Run: `xcodebuild … build` → `** BUILD SUCCEEDED **`. Di Settings > Agents, klik "Pasang hooks" untuk Claude Code dan Codex.
Expected: status berubah "Terpasang"; file cadangan ada; `python3 -I -m json.tool ~/.claude/settings.json` valid dan hooks plugin lain tetap ada; `diff` antara cadangan dan file baru hanya berisi grup `notch-report` (abaikan urutan key). "Lepas hooks" → grup `notch-report` hilang, sisanya sama dengan cadangan (abaikan urutan key). Pasang kembali setelah pengecekan.

- [ ] **Step 5: Commit**

```bash
git add boringNotch/managers/AgentMonitor boringNotch/components/Settings
git commit -m "feat(agents): add agents settings and hook installer"
```

---

### Task 12: Uji end-to-end

**Files:** tidak ada perubahan kecuali perbaikan bug yang ditemukan (masing-masing dengan test di paket bila logikanya ada di `AgentMonitorKit`).

- [ ] **Step 1: Jalankan semua test paket**

Run: `cd AgentMonitorKit && swift test`
Expected: semua PASS.

- [ ] **Step 2: Jalankan daftar uji manual spec bagian 8 (langkah 1–9)**

Catat hasil tiap langkah (lulus/gagal + pengamatan) di deskripsi commit atau catatan sesi.

- [ ] **Step 3: Logo Codex**

Bila pengguna sudah menyediakan file logo, pilih lewat Settings > Agents > Codex > "Pilih logo…".
Expected: baris dan notifikasi Codex memakai logo itu.

- [ ] **Step 4: Review seluruh branch**

Jalankan review menyeluruh terhadap `git diff upstream/main...mynotch` sebelum menyatakan selesai.
