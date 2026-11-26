import Defaults
import SwiftUI

struct DiscordSettingsView: View {
    @Default(.discordApplicationID) private var applicationID
    @Default(.discordAppleMusicPresenceEnabled) private var appleMusicPresenceEnabled
    @Default(.discordVoiceEnabled) private var voiceEnabled

    @ObservedObject private var discordManager = DiscordIntegrationManager.shared

    @State private var clientSecretInput: String = ""
    @State private var hasStoredSecret: Bool = false
    @State private var secretFeedback: String?

    var body: some View {
        Form {
            Section {
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

                HStack {
                    Text("Status IPC")
                    Spacer()
                    Text(discordManager.connectionState.label)
                        .foregroundStyle(statusColor)
                }

                if let secretFeedback {
                    Text(secretFeedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Di Discord Developer Portal → OAuth2, tambahkan Redirect URI: http://127.0.0.1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Aplikasi Discord")
            }

            Section {
                Defaults.Toggle(key: .discordAppleMusicPresenceEnabled) {
                    Text("Tampilkan lagu Apple Music di profil")
                }
                Text("Mengirim aktivitas Listening saat Apple Music memutar lagu. Hanya membutuhkan Application ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Rich Presence")
            }

            Section {
                Defaults.Toggle(key: .discordVoiceEnabled) {
                    Text("Tampilkan status voice di notch")
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

                Text("Membutuhkan izin satu kali di dialog aplikasi Discord desktop.")
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

    private var statusColor: Color {
        switch discordManager.connectionState {
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
