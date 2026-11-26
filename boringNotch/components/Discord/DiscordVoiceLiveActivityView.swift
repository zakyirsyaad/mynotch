import AgentMonitorKit
import SwiftUI

struct DiscordVoiceLiveActivityView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var discordManager = DiscordIntegrationManager.shared

    private var voiceState: DiscordVoiceState {
        discordManager.voiceState
    }

    private var effectiveMuted: Bool {
        voiceState.isMuted || voiceState.isDeafened
    }

    private var wingSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var iconName: String {
        if voiceState.isDeafened {
            return "speaker.slash.fill"
        }
        return effectiveMuted ? "mic.slash.fill" : "mic.fill"
    }

    private var iconColor: Color {
        (voiceState.isDeafened || effectiveMuted) ? .red : .green
    }

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: wingSize, height: wingSize, alignment: .center)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Group {
                if voiceState.isAnyoneSpeaking && !voiceState.isDeafened {
                    AudioSpectrumView(isPlaying: .constant(true))
                        .frame(width: 16, height: 12)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: wingSize, height: wingSize, alignment: .center)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
