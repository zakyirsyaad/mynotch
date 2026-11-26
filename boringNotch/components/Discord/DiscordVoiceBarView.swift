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
        HStack(spacing: 8) {
            Button {
                discordManager.openDiscordApp()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: voiceState.isDeafened ? "speaker.slash.fill" : (effectiveMuted ? "mic.slash.fill" : "mic.fill"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 18, height: 18)

                    Text(voiceState.channelName ?? "Discord Voice")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                Button {
                    discordManager.toggleMute()
                } label: {
                    Circle()
                        .fill(effectiveMuted ? Color.red.opacity(0.25) : Color.white.opacity(0.10))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: effectiveMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 10.5, weight: .semibold))
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
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: voiceState.isDeafened ? "speaker.slash.fill" : "headphones")
                                .font(.system(size: 10.5, weight: .semibold))
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
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)
                .help("Leave Voice")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
