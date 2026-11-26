import AgentMonitorKit
import AppKit
import Combine
import Defaults
import Foundation
import os

@MainActor
final class DiscordIntegrationManager: ObservableObject {
    static let shared = DiscordIntegrationManager()

    @Published private(set) var musicConnectionState: DiscordIPCConnectionState = .disabled
    @Published private(set) var activePlayerName: String?
    @Published private(set) var connectionState: DiscordIPCConnectionState = .disabled
    @Published private(set) var voiceState = DiscordVoiceState()
    @Published private(set) var isVoiceAuthorized: Bool = false
    @Published private(set) var authError: String?

    private let musicClient = DiscordIPCClient()
    private let voiceClient = DiscordIPCClient()
    private let logger = Logger(subsystem: bundleIdentifier, category: "Discord")
    private var cancellables: Set<AnyCancellable> = []
    private var isStarted = false

    // Music Presence state
    private var presenceTask: Task<Void, Never>?
    private var activeMusicClientID: String = ""
    private var lastSentActivity: DiscordPresenceActivity?
    private var didSendActivityOnce = false

    // Voice RPC state
    private var activeVoiceClientID: String = ""
    private var pendingAuthorizeNonce: String?
    private var pendingAuthenticateNonce: String?
    private var hasAttemptedRefreshThisConnection = false
    private var isAuthenticatedOnCurrentConnection = false
    private var subscribedSpeakingChannelID: String?
    private var hasSubscribedGlobalVoiceEvents = false

    private init() {
        isVoiceAuthorized = KeychainSecretStore.load(account: KeychainSecretStore.accessTokenAccount) != nil

        musicClient.onConnectionStateChanged = { [weak self] newState in
            self?.handleMusicConnectionStateChanged(newState)
        }

        voiceClient.onConnectionStateChanged = { [weak self] newState in
            self?.handleVoiceConnectionStateChanged(newState)
        }
        voiceClient.onMessage = { [weak self] message in
            self?.handleVoiceIPCMessage(message)
        }

        observeSettings()
        observeMusicChanges()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        syncVoiceConnectionWithSettings()
        schedulePresenceUpdate()
    }

    func stop() {
        isStarted = false
        presenceTask?.cancel()
        presenceTask = nil

        clearMusicPresenceAndDisconnect(synchronous: true)

        unsubscribeVoiceEvents()
        voiceClient.stopSync()
        voiceState = DiscordVoiceState()
        isAuthenticatedOnCurrentConnection = false
        activeVoiceClientID = ""
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
        voiceClient.sendJSON(
            DiscordIPCFramer.authorizePayload(
                clientID: clientID,
                scopes: ["rpc", "rpc.voice.read", "rpc.voice.write"],
                nonce: nonce
            )
        )
    }

    func disconnectVoiceAuth() {
        unsubscribeVoiceEvents()
        KeychainSecretStore.delete(account: KeychainSecretStore.accessTokenAccount)
        KeychainSecretStore.delete(account: KeychainSecretStore.refreshTokenAccount)
        isVoiceAuthorized = false
        isAuthenticatedOnCurrentConnection = false
        voiceState = DiscordVoiceState(currentUserID: voiceState.currentUserID)
        authError = nil
    }

    func toggleMute() {
        guard isAuthenticatedOnCurrentConnection, voiceState.isInVoice else { return }
        let nextMute = !(voiceState.isMuted || voiceState.isDeafened)
        voiceClient.sendJSON(
            DiscordIPCFramer.setVoiceSettingsPayload(
                mute: nextMute,
                deaf: nextMute ? nil : false,
                nonce: UUID().uuidString
            )
        )
    }

    func toggleDeafen() {
        guard isAuthenticatedOnCurrentConnection, voiceState.isInVoice else { return }
        voiceClient.sendJSON(
            DiscordIPCFramer.setVoiceSettingsPayload(
                mute: nil,
                deaf: !voiceState.isDeafened,
                nonce: UUID().uuidString
            )
        )
    }

    func leaveVoiceChannel() {
        guard isAuthenticatedOnCurrentConnection, voiceState.isInVoice else { return }
        voiceClient.sendJSON(
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

    // MARK: - Observers

    private func observeSettings() {
        let debouncedAppID = Defaults.publisher(.discordApplicationID)
            .map(\.newValue)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)

        Publishers.CombineLatest(
            debouncedAppID,
            Defaults.publisher(.discordVoiceEnabled).map(\.newValue)
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.syncVoiceConnectionWithSettings()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            Defaults.publisher(.discordAppleMusicPresenceEnabled).map(\.newValue),
            Defaults.publisher(.discordMusicStatusDisplayType).map(\.newValue),
            Defaults.publisher(.discordMusicShowAlbumName).map(\.newValue),
            Defaults.publisher(.discordMusicShowSongLink).map(\.newValue)
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.schedulePresenceUpdate()
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
        .combineLatest(music.$timestampDate)
        .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.schedulePresenceUpdate()
        }
        .store(in: &cancellables)
    }

    // MARK: - Music Rich Presence (Zero-Config Multi-Player IPC)

    private func handleMusicConnectionStateChanged(_ newState: DiscordIPCConnectionState) {
        musicConnectionState = newState
        if newState != .connected {
            lastSentActivity = nil
            didSendActivityOnce = false
        } else {
            schedulePresenceUpdate()
        }
    }

    private func clearMusicPresenceAndDisconnect(synchronous: Bool = false) {
        let shouldClear = musicConnectionState == .connected && didSendActivityOnce && lastSentActivity != nil
        let clearPayload: JSONValue? = shouldClear
            ? DiscordIPCFramer.setActivityPayload(
                pid: ProcessInfo.processInfo.processIdentifier,
                nonce: UUID().uuidString,
                activity: nil
            )
            : nil

        lastSentActivity = nil
        didSendActivityOnce = false
        activeMusicClientID = ""
        activePlayerName = nil
        if synchronous {
            musicClient.stopSync(sendingFinalPayload: clearPayload)
        } else {
            if let clearPayload {
                musicClient.sendJSON(clearPayload)
            }
            musicClient.stop()
        }
        musicConnectionState = .disabled
    }

    private func schedulePresenceUpdate() {
        guard isStarted else { return }
        presenceTask?.cancel()

        guard Defaults[.discordAppleMusicPresenceEnabled] else {
            clearMusicPresenceAndDisconnect()
            return
        }

        let music = MusicManager.shared
        let isActivelyPlaying = music.isPlaying && !music.isPlayerIdle
        let resolvedPlayer = isActivelyPlaying
            ? DiscordMediaPlayerRegistry.resolve(bundleIdentifier: music.bundleIdentifier)
            : nil

        guard let player = resolvedPlayer else {
            activePlayerName = nil
            if musicConnectionState == .connected && didSendActivityOnce && lastSentActivity != nil {
                lastSentActivity = nil
                musicClient.sendJSON(
                    DiscordIPCFramer.setActivityPayload(
                        pid: ProcessInfo.processInfo.processIdentifier,
                        nonce: UUID().uuidString,
                        activity: nil
                    )
                )
            }
            return
        }

        activePlayerName = player.name
        if activeMusicClientID != player.applicationID {
            activeMusicClientID = player.applicationID
            lastSentActivity = nil
            didSendActivityOnce = false
            musicClient.updateClientID(player.applicationID)
            return
        }

        guard musicConnectionState == .connected else { return }

        let options = DiscordMusicPresenceOptions(
            statusDisplayType: DiscordStatusDisplayType(rawValue: Defaults[.discordMusicStatusDisplayType]) ?? .playerName,
            showAlbumName: Defaults[.discordMusicShowAlbumName],
            showPlaybackDuration: true,
            showSongLinkButton: Defaults[.discordMusicShowSongLink]
        )

        let trackSnapshot = DiscordMusicTrack(
            title: music.songTitle,
            artist: music.artistName,
            album: music.album,
            duration: music.songDuration,
            elapsed: music.elapsedTime,
            timestampDate: music.timestampDate,
            playbackRate: music.playbackRate,
            isPlaying: isActivelyPlaying,
            bundleIdentifier: music.bundleIdentifier
        )

        presenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let meta = await AppleMusicArtworkResolver.shared.metadata(
                artist: trackSnapshot.artist,
                title: trackSnapshot.title
            )
            guard !Task.isCancelled,
                  self.musicConnectionState == .connected,
                  self.activeMusicClientID == player.applicationID
            else { return }

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
                artworkURL: meta.artworkURL,
                trackURL: meta.trackURL
            )

            let activity = DiscordMusicPresenceFormatter.activity(
                from: enrichedTrack,
                enabled: Defaults[.discordAppleMusicPresenceEnabled],
                options: options,
                now: Date()
            )

            if self.didSendActivityOnce && self.lastSentActivity == activity {
                return
            }

            self.didSendActivityOnce = true
            self.lastSentActivity = activity
            self.musicClient.sendJSON(
                DiscordIPCFramer.setActivityPayload(
                    pid: ProcessInfo.processInfo.processIdentifier,
                    nonce: UUID().uuidString,
                    activity: activity
                )
            )
        }
    }

    // MARK: - Voice RPC (OAuth2 IPC)

    private func syncVoiceConnectionWithSettings() {
        guard isStarted else { return }

        let voiceEnabled = Defaults[.discordVoiceEnabled]
        let clientID = Defaults[.discordApplicationID].trimmingCharacters(in: .whitespacesAndNewlines)

        guard voiceEnabled, !clientID.isEmpty else {
            unsubscribeVoiceEvents()
            voiceClient.stop()
            voiceState = DiscordVoiceState()
            isAuthenticatedOnCurrentConnection = false
            activeVoiceClientID = ""
            connectionState = .disabled
            return
        }

        let clientChanged = (clientID != activeVoiceClientID)
        activeVoiceClientID = clientID
        voiceClient.updateClientID(clientID)

        if !clientChanged && connectionState == .connected && !isAuthenticatedOnCurrentConnection {
            authenticateIfPossible()
        }
    }

    private func handleVoiceConnectionStateChanged(_ newState: DiscordIPCConnectionState) {
        connectionState = newState
        if newState != .connected {
            isAuthenticatedOnCurrentConnection = false
            hasAttemptedRefreshThisConnection = false
            hasSubscribedGlobalVoiceEvents = false
            subscribedSpeakingChannelID = nil
            pendingAuthorizeNonce = nil
            pendingAuthenticateNonce = nil
            voiceState = DiscordVoiceState()
        } else if Defaults[.discordVoiceEnabled] {
            authenticateIfPossible()
        }
    }

    private func handleVoiceIPCMessage(_ message: JSONValue) {
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

        if evt == "READY" {
            voiceState = DiscordVoiceReducer.reducing(voiceState, message: message)
            return
        }

        guard isAuthenticatedOnCurrentConnection && Defaults[.discordVoiceEnabled] else {
            return
        }

        let previousChannelID = voiceState.channelID
        voiceState = DiscordVoiceReducer.reducing(voiceState, message: message)

        if voiceState.channelID != previousChannelID {
            syncSpeakingSubscription(for: voiceState.channelID)
            if voiceState.channelID != nil && voiceState.channelName == nil {
                voiceClient.sendJSON(DiscordIPCFramer.getSelectedVoiceChannelPayload(nonce: UUID().uuidString))
            }
        }
    }

    private func authenticateIfPossible() {
        guard let token = KeychainSecretStore.load(account: KeychainSecretStore.accessTokenAccount) else {
            isVoiceAuthorized = false
            return
        }
        isVoiceAuthorized = true
        let nonce = UUID().uuidString
        pendingAuthenticateNonce = nonce
        voiceClient.sendJSON(DiscordIPCFramer.authenticatePayload(accessToken: token, nonce: nonce))
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
            "VOICE_SETTINGS_UPDATE"
        ]
        for event in events {
            voiceClient.sendJSON(DiscordIPCFramer.subscribePayload(event: event, nonce: UUID().uuidString))
        }
        hasSubscribedGlobalVoiceEvents = true
        voiceClient.sendJSON(DiscordIPCFramer.getSelectedVoiceChannelPayload(nonce: UUID().uuidString))
        voiceClient.sendJSON(DiscordIPCFramer.getVoiceSettingsPayload(nonce: UUID().uuidString))
    }

    private func unsubscribeVoiceEvents() {
        syncSpeakingSubscription(for: nil)
        guard hasSubscribedGlobalVoiceEvents else { return }
        hasSubscribedGlobalVoiceEvents = false
        guard connectionState == .connected else { return }
        for event in ["VOICE_CHANNEL_SELECT", "VOICE_SETTINGS_UPDATE"] {
            voiceClient.sendJSON(DiscordIPCFramer.unsubscribePayload(event: event, nonce: UUID().uuidString))
        }
    }

    private func syncSpeakingSubscription(for channelID: String?) {
        guard subscribedSpeakingChannelID != channelID else { return }
        if let oldChannelID = subscribedSpeakingChannelID, connectionState == .connected {
            let args: [String: JSONValue] = ["channel_id": .string(oldChannelID)]
            voiceClient.sendJSON(DiscordIPCFramer.unsubscribePayload(event: "SPEAKING_START", args: args, nonce: UUID().uuidString))
            voiceClient.sendJSON(DiscordIPCFramer.unsubscribePayload(event: "SPEAKING_STOP", args: args, nonce: UUID().uuidString))
        }
        subscribedSpeakingChannelID = channelID
        if let newChannelID = channelID, connectionState == .connected {
            let args: [String: JSONValue] = ["channel_id": .string(newChannelID)]
            voiceClient.sendJSON(DiscordIPCFramer.subscribePayload(event: "SPEAKING_START", args: args, nonce: UUID().uuidString))
            voiceClient.sendJSON(DiscordIPCFramer.subscribePayload(event: "SPEAKING_STOP", args: args, nonce: UUID().uuidString))
        }
    }
}
