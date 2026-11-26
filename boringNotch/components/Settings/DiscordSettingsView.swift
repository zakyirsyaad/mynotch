import Defaults
import SwiftUI

struct DiscordSettingsView: View {
    @Default(.discordApplicationID) private var applicationID
    @Default(.discordAppleMusicPresenceEnabled) private var musicPresenceEnabled
    @Default(.discordMusicStatusDisplayType) private var statusDisplayType
    @Default(.discordMusicShowAlbumName) private var showAlbumName
    @Default(.discordMusicShowSongLink) private var showSongLink
    @Default(.discordVoiceEnabled) private var voiceEnabled

    @ObservedObject private var discordManager = DiscordIntegrationManager.shared

    @State private var clientSecretInput: String = ""
    @State private var hasStoredSecret: Bool = false
    @State private var secretFeedback: String?

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .discordAppleMusicPresenceEnabled) {
                    Text("Tampilkan lagu yang diputar di profil")
                }

                HStack {
                    Text("Status Music Presence")
                    Spacer()
                    Text(musicStatusLabel)
                        .foregroundStyle(musicStatusColor)
                }

                Picker("Teks di daftar member", selection: $statusDisplayType) {
                    Text("Nama Player (mis. Apple Music)").tag(0)
                    Text("Nama Artis").tag(1)
                    Text("Judul Lagu").tag(2)
                }
                .disabled(!musicPresenceEnabled)

                Defaults.Toggle(key: .discordMusicShowAlbumName) {
                    Text("Tampilkan nama album")
                }
                .disabled(!musicPresenceEnabled)

                Defaults.Toggle(key: .discordMusicShowSongLink) {
                    Text("Tampilkan tombol link lagu")
                }
                .disabled(!musicPresenceEnabled)

                Text("Otomatis mendukung Apple Music, Spotify, YouTube Music, TIDAL, Deezer, Cider, VLC, dan lainnya tanpa perlu membuat Application ID. Matikan aplikasi Music Presence terpisah agar tidak bentrok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Music Rich Presence")
            }

            Section {
                Defaults.Toggle(key: .discordVoiceEnabled) {
                    Text("Tampilkan status voice di notch")
                }

                TextField("Discord Application ID", text: $applicationID)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    SecureField(
                        hasStoredSecret ? "Client Secret tersimpan di Keychain" : "Client Secret (untuk Voice RPC)",
                        text: $clientSecretInput
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Simpan") {
                        saveSecret()
                    }
                    .disabled(clientSecretInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasStoredSecret {
                        Button("Hapus", role: .destructive) {
                            discordManager.deleteClientSecret()
                            hasStoredSecret = false
                            secretFeedback = "Client Secret dihapus dari Keychain."
                        }
                    }
                }

                if let secretFeedback {
                    Text(secretFeedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Status Voice IPC")
                    Spacer()
                    Text(discordManager.connectionState.label)
                        .foregroundStyle(statusColor(for: discordManager.connectionState))
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Otorisasi Voice RPC")
                        Text(discordManager.isVoiceAuthorized ? "Terotorisasi" : "Belum diotorisasi")
                            .font(.caption)
                            .foregroundStyle(discordManager.isVoiceAuthorized ? .green : .secondary)
                    }
                    Spacer()
                    if discordManager.isVoiceAuthorized {
                        Button("Putuskan", role: .destructive) {
                            discordManager.disconnectVoiceAuth()
                        }
                    } else {
                        Button("Hubungkan Voice RPC") {
                            discordManager.authorizeVoiceRPC()
                        }
                        .disabled(!voiceEnabled)
                    }
                }

                if !voiceEnabled && !discordManager.isVoiceAuthorized {
                    Text("Aktifkan toggle voice di atas terlebih dahulu untuk menghubungkan Voice RPC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let authError = discordManager.authError {
                    Text(authError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Voice RPC membutuhkan Application ID & Client Secret dari Discord Developer Portal (OAuth2 Redirect URI: http://127.0.0.1).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Voice Call di Notch")
            }
        }
        .navigationTitle("Discord")
        .onAppear {
            hasStoredSecret = discordManager.hasClientSecret()
        }
    }

    private var musicStatusLabel: String {
        guard musicPresenceEnabled else { return "Nonaktif" }
        switch discordManager.musicConnectionState {
        case .connected:
            if let player = discordManager.activePlayerName {
                return "Terhubung · \(player)"
            }
            return "Terhubung"
        case .waitingForDiscord:
            return "Menunggu Discord…"
        case .disabled:
            return "Menunggu lagu diputar…"
        case .error(let message):
            return message
        }
    }

    private var musicStatusColor: Color {
        guard musicPresenceEnabled else { return .secondary }
        return statusColor(for: discordManager.musicConnectionState)
    }

    private func statusColor(for state: DiscordIPCConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .waitingForDiscord:
            return .orange
        case .disabled:
            return .secondary
        case .error:
            return .red
        }
    }

    private func saveSecret() {
        do {
            try discordManager.saveClientSecret(clientSecretInput)
            clientSecretInput = ""
            hasStoredSecret = discordManager.hasClientSecret()
            secretFeedback = "Client Secret tersimpan aman di Keychain."
        } catch {
            secretFeedback = error.localizedDescription
        }
    }
}
