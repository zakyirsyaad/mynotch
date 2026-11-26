import AgentMonitorKit
import SwiftUI

struct DiscordVoiceBarView: View {
    @ObservedObject private var discordManager = DiscordIntegrationManager.shared

    private var voiceState: DiscordVoiceState {
        discordManager.voiceState
    }

    private var effectiveMuted: Bool {
        voiceState.isMuted || voiceState.isDeafened
    }

    private var statusText: String {
        if voiceState.isDeafened {
            return "Deafened · Discord"
        }
        if effectiveMuted {
            return "Muted · Discord"
        }
        if voiceState.isAnyoneSpeaking {
            return "Berbicara · Discord"
        }
        return "Terhubung · Discord"
    }

    private var statusColor: Color {
        (voiceState.isDeafened || effectiveMuted) ? .red : .green
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                discordManager.openDiscordApp()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: voiceState.isDeafened ? "speaker.slash.fill" : (effectiveMuted ? "mic.slash.fill" : "mic.fill"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(voiceState.channelName ?? "Discord Voice")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    discordManager.toggleMute()
                } label: {
                    Circle()
                        .fill(effectiveMuted ? Color.red.opacity(0.25) : Color.white.opacity(0.10))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: effectiveMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(effectiveMuted ? Color.red : Color.white)
                        }
                }
                .buttonStyle(.plain)
                .help(effectiveMuted ? "Unmute" : "Mute")

                Button {
                    discordManager.toggleDeafen()
                } label: {
                    Circle()
                        .fill(voiceState.isDeafened ? Color.red.opacity(0.25) : Color.white.opacity(0.10))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: voiceState.isDeafened ? "speaker.slash.fill" : "headphones")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(voiceState.isDeafened ? Color.red : Color.white)
                        }
                }
                .buttonStyle(.plain)
                .help(voiceState.isDeafened ? "Undeafen" : "Deafen")

                Button {
                    discordManager.leaveVoiceChannel()
                } label: {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)
                .help("Leave Voice")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
