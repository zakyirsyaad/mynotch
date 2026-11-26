import AgentMonitorKit
import AppKit
import Combine
import Defaults
import Foundation
import os

@MainActor
final class DiscordIntegrationManager: ObservableObject {
    static let shared = DiscordIntegrationManager()

    @Published private(set) var connectionState: DiscordIPCConnectionState = .disabled
    @Published private(set) var voiceState = DiscordVoiceState()
    @Published private(set) var isVoiceAuthorized: Bool = false
    @Published private(set) var authError: String?

    private let client = DiscordIPCClient()
    private let logger = Logger(subsystem: bundleIdentifier, category: "Discord")
    private var cancellables: Set<AnyCancellable> = []
    private var isStarted = false
    private var presenceTask: Task<Void, Never>?
    private var lastSentActivity: DiscordPresenceActivity?
    private var didSendActivityOnce = false
    private var pendingAuthorizeNonce: String?
    private var pendingAuthenticateNonce: String?
    private var hasAttemptedRefreshThisConnection = false
    private var isAuthenticatedOnCurrentConnection = false

    private init() {
        isVoiceAuthorized = KeychainSecretStore.load(account: KeychainSecretStore.accessTokenAccount) != nil

        client.onConnectionStateChanged = { [weak self] newState in
            self?.handleConnectionStateChanged(newState)
        }
        client.onMessage = { [weak self] message in
            self?.handleIPCMessage(message)
        }

        observeSettings()
        observeMusicChanges()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        syncConnectionWithSettings()
    }

    func stop() {
        isStarted = false
        presenceTask?.cancel()
        presenceTask = nil
        client.stop()
        voiceState = DiscordVoiceState()
        lastSentActivity = nil
        didSendActivityOnce = false
        isAuthenticatedOnCurrentConnection = false
    }

    func saveClientSecret(_ secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainSecretStore.delete(account: KeychainSecretStore.clientSecretAccount)
        } else {
            try KeychainSecretStore.save(trimmed, account: KeychainSecretStore.clientSecretAccount)
        }
    }

    func hasClientSecret() -> Bool {
        KeychainSecretStore.load(account: KeychainSecretStore.clientSecretAccount) != nil
    }

    func deleteClientSecret() {
        KeychainSecretStore.delete(account: KeychainSecretStore.clientSecretAccount)
    }

    func authorizeVoiceRPC() {
        authError = nil
        let clientID = Defaults[.discordApplicationID].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            authError = "Isi Discord Application ID terlebih dahulu."
            return
        }
        guard hasClientSecret() else {
            authError = "Simpan Client Secret di Keychain terlebih dahulu."
            return
        }
        guard connectionState == .connected else {
            authError = "Discord desktop belum terhubung."
            return
        }

        let nonce = UUID().uuidString
        pendingAuthorizeNonce = nonce
        client.sendJSON(
            DiscordIPCFramer.authorizePayload(
                clientID: clientID,
                scopes: ["rpc", "rpc.voice.read", "rpc.voice.write"],
                nonce: nonce
            )
        )
    }

    func disconnectVoiceAuth() {
        KeychainSecretStore.delete(account: KeychainSecretStore.accessTokenAccount)
        KeychainSecretStore.delete(account: KeychainSecretStore.refreshTokenAccount)
        isVoiceAuthorized = false
        isAuthenticatedOnCurrentConnection = false
        voiceState = DiscordVoiceState()
        authError = nil
    }

    func toggleMute() {
        guard isAuthenticatedOnCurrentConnection, voiceState.isInVoice else { return }
        let nextMute = !(voiceState.isMuted || voiceState.isDeafened)
        client.sendJSON(
            DiscordIPCFramer.setVoiceSettingsPayload(
                mute: nextMute,
                deaf: nextMute ? nil : false,
                nonce: UUID().uuidString
            )
        )
    }

    func toggleDeafen() {
        guard isAuthenticatedOnCurrentConnection, voiceState.isInVoice else { return }
        client.sendJSON(
            DiscordIPCFramer.setVoiceSettingsPayload(
                mute: nil,
                deaf: !voiceState.isDeafened,
                nonce: UUID().uuidString
            )
        )
    }

    func leaveVoiceChannel() {
        guard isAuthenticatedOnCurrentConnection, voiceState.isInVoice else { return }
        client.sendJSON(
            DiscordIPCFramer.selectVoiceChannelPayload(channelID: nil, nonce: UUID().uuidString)
        )
    }

    func openDiscordApp() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.hnc.Discord").first {
            app.activate(options: [.activateAllWindows])
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hnc.Discord") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func observeSettings() {
        Publishers.CombineLatest3(
            Defaults.publisher(.discordApplicationID).map(\.newValue),
            Defaults.publisher(.discordAppleMusicPresenceEnabled).map(\.newValue),
            Defaults.publisher(.discordVoiceEnabled).map(\.newValue)
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            self?.syncConnectionWithSettings()
        }
        .store(in: &cancellables)
    }

    private func observeMusicChanges() {
        let music = MusicManager.shared
        Publishers.CombineLatest4(
            music.$songTitle,
            music.$artistName,
            music.$album,
            music.$isPlaying
        )
        .combineLatest(
            Publishers.CombineLatest4(
                music.$isPlayerIdle,
                music.$bundleIdentifier,
                music.$songDuration,
                music.$elapsedTime
            )
        )
        .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.schedulePresenceUpdate()
        }
        .store(in: &cancellables)
    }

    private func syncConnectionWithSettings() {
        guard isStarted else { return }

        let musicEnabled = Defaults[.discordAppleMusicPresenceEnabled]
        let voiceEnabled = Defaults[.discordVoiceEnabled]
        let clientID = Defaults[.discordApplicationID].trimmingCharacters(in: .whitespacesAndNewlines)

        guard (musicEnabled || voiceEnabled), !clientID.isEmpty else {
            presenceTask?.cancel()
            client.stop()
            voiceState = DiscordVoiceState()
            lastSentActivity = nil
            didSendActivityOnce = false
            isAuthenticatedOnCurrentConnection = false
            connectionState = .disabled
            return
        }

        client.updateClientID(clientID)
        if connectionState == .connected {
            schedulePresenceUpdate()
            if voiceEnabled && !isAuthenticatedOnCurrentConnection {
                authenticateIfPossible()
            } else if !voiceEnabled {
                voiceState = DiscordVoiceState()
            }
        }
    }

    private func handleConnectionStateChanged(_ newState: DiscordIPCConnectionState) {
        connectionState = newState
        if newState != .connected {
            isAuthenticatedOnCurrentConnection = false
            hasAttemptedRefreshThisConnection = false
            pendingAuthorizeNonce = nil
            pendingAuthenticateNonce = nil
            lastSentActivity = nil
            didSendActivityOnce = false
            voiceState = DiscordVoiceState()
        } else {
            schedulePresenceUpdate()
            if Defaults[.discordVoiceEnabled] {
                authenticateIfPossible()
            }
        }
    }

    private func handleIPCMessage(_ message: JSONValue) {
        let cmd = message["cmd"]?.stringValue
        let evt = message["evt"]?.stringValue
        let nonce = message["nonce"]?.stringValue

        if cmd == "AUTHORIZE", let nonce, nonce == pendingAuthorizeNonce {
            pendingAuthorizeNonce = nil
            if evt == "ERROR" {
                authError = message["data"]?["message"]?.stringValue ?? "Otorisasi Discord ditolak."
                return
            }
            if let code = message["data"]?["code"]?.stringValue {
                Task { [weak self] in
                    await self?.completeOAuthExchange(code: code)
                }
            }
            return
        }

        if cmd == "AUTHENTICATE", let nonce, nonce == pendingAuthenticateNonce {
            pendingAuthenticateNonce = nil
            if evt == "ERROR" {
                handleAuthenticateFailure(message: message)
                return
            }
            isAuthenticatedOnCurrentConnection = true
            authError = nil
            subscribeToVoiceEvents()
            return
        }

        voiceState = DiscordVoiceReducer.reducing(voiceState, message: message)
    }

    private func authenticateIfPossible() {
        guard let token = KeychainSecretStore.load(account: KeychainSecretStore.accessTokenAccount) else {
            isVoiceAuthorized = false
            return
        }
        isVoiceAuthorized = true
        let nonce = UUID().uuidString
        pendingAuthenticateNonce = nonce
        client.sendJSON(DiscordIPCFramer.authenticatePayload(accessToken: token, nonce: nonce))
    }

    private func completeOAuthExchange(code: String) async {
        let clientID = Defaults[.discordApplicationID].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let secret = KeychainSecretStore.load(account: KeychainSecretStore.clientSecretAccount) else {
            authError = DiscordOAuthError.missingClientSecret.localizedDescription
            return
        }

        do {
            let tokens = try await DiscordOAuthService.exchangeCode(code, clientID: clientID, clientSecret: secret)
            try KeychainSecretStore.save(tokens.accessToken, account: KeychainSecretStore.accessTokenAccount)
            if let refresh = tokens.refreshToken {
                try KeychainSecretStore.save(refresh, account: KeychainSecretStore.refreshTokenAccount)
            }
            isVoiceAuthorized = true
            authError = nil
            authenticateIfPossible()
        } catch {
            authError = error.localizedDescription
            logger.error("Discord OAuth code exchange failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleAuthenticateFailure(message: JSONValue) {
        if !hasAttemptedRefreshThisConnection,
           let refreshToken = KeychainSecretStore.load(account: KeychainSecretStore.refreshTokenAccount),
           let secret = KeychainSecretStore.load(account: KeychainSecretStore.clientSecretAccount)
        {
            hasAttemptedRefreshThisConnection = true
            let clientID = Defaults[.discordApplicationID].trimmingCharacters(in: .whitespacesAndNewlines)
            Task { [weak self] in
                guard let self else { return }
                do {
                    let tokens = try await DiscordOAuthService.refreshAccessToken(
                        refreshToken,
                        clientID: clientID,
                        clientSecret: secret
                    )
                    try KeychainSecretStore.save(tokens.accessToken, account: KeychainSecretStore.accessTokenAccount)
                    if let nextRefresh = tokens.refreshToken {
                        try KeychainSecretStore.save(nextRefresh, account: KeychainSecretStore.refreshTokenAccount)
                    }
                    self.authenticateIfPossible()
                } catch {
                    self.disconnectVoiceAuth()
                    self.authError = "Sesi Voice RPC kedaluwarsa, silakan hubungkan ulang."
                }
            }
        } else {
            disconnectVoiceAuth()
            authError = message["data"]?["message"]?.stringValue ?? "Autentikasi Voice RPC gagal."
        }
    }

    private func subscribeToVoiceEvents() {
        let events = [
            "VOICE_CHANNEL_SELECT",
            "VOICE_SETTINGS_UPDATE",
            "SPEAKING_START",
            "SPEAKING_STOP"
        ]
        for event in events {
            client.sendJSON(DiscordIPCFramer.subscribePayload(event: event, nonce: UUID().uuidString))
        }
        client.sendJSON(DiscordIPCFramer.getSelectedVoiceChannelPayload(nonce: UUID().uuidString))
        client.sendJSON(DiscordIPCFramer.getVoiceSettingsPayload(nonce: UUID().uuidString))
    }

    private func schedulePresenceUpdate() {
        presenceTask?.cancel()
        guard connectionState == .connected else { return }

        let enabled = Defaults[.discordAppleMusicPresenceEnabled]
        guard enabled else {
            if didSendActivityOnce && lastSentActivity != nil {
                lastSentActivity = nil
                client.sendJSON(
                    DiscordIPCFramer.setActivityPayload(
                        pid: ProcessInfo.processInfo.processIdentifier,
                        nonce: UUID().uuidString,
                        activity: nil
                    )
                )
            }
            return
        }

        let music = MusicManager.shared
        let trackSnapshot = DiscordMusicTrack(
            title: music.songTitle,
            artist: music.artistName,
            album: music.album,
            duration: music.songDuration,
            elapsed: music.elapsedTime,
            timestampDate: music.timestampDate,
            playbackRate: music.playbackRate,
            isPlaying: music.isPlaying && !music.isPlayerIdle,
            bundleIdentifier: music.bundleIdentifier,
            artworkURL: nil
        )

        presenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let artworkURL: String?
            if trackSnapshot.isPlaying && trackSnapshot.bundleIdentifier == DiscordMusicPresenceFormatter.appleMusicBundleID {
                artworkURL = await AppleMusicArtworkResolver.shared.artworkURL(
                    artist: trackSnapshot.artist,
                    title: trackSnapshot.title
                )
            } else {
                artworkURL = nil
            }
            guard !Task.isCancelled, self.connectionState == .connected else { return }

            let enrichedTrack = DiscordMusicTrack(
                title: trackSnapshot.title,
                artist: trackSnapshot.artist,
                album: trackSnapshot.album,
                duration: trackSnapshot.duration,
                elapsed: trackSnapshot.elapsed,
                timestampDate: trackSnapshot.timestampDate,
                playbackRate: trackSnapshot.playbackRate,
                isPlaying: trackSnapshot.isPlaying,
                bundleIdentifier: trackSnapshot.bundleIdentifier,
                artworkURL: artworkURL
            )

            let activity = DiscordMusicPresenceFormatter.activity(
                from: enrichedTrack,
                enabled: Defaults[.discordAppleMusicPresenceEnabled],
                now: Date()
            )

            if self.didSendActivityOnce && self.lastSentActivity == activity {
                return
            }

            self.didSendActivityOnce = true
            self.lastSentActivity = activity
            self.client.sendJSON(
                DiscordIPCFramer.setActivityPayload(
                    pid: ProcessInfo.processInfo.processIdentifier,
                    nonce: UUID().uuidString,
                    activity: activity
                )
            )
        }
    }
}
