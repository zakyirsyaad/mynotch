import AgentMonitorKit
import SwiftUI

struct AgentRowView: View {
    let session: AgentSession
    let now: Date

    @ObservedObject private var manager = AgentMonitorManager.shared
    @ObservedObject private var iconProvider = AgentIconProvider.shared
    @State private var pulse = false

    private var titleText: String {
        let name = manager.displayName(for: session.agentID)
        if let cwd = session.cwdName, !cwd.isEmpty {
            return "\(name) · \(cwd)"
        }
        return name
    }

    private var subtitleText: String {
        let base: String
        if let detail = session.detail, !detail.isEmpty {
            base = detail
        } else if session.origin == .process {
            base = "Terdeteksi dari proses"
        } else {
            base = session.status.label
        }

        if session.subagentCount > 0 {
            return "\(base) · \(session.subagentCount) subagent"
        }
        return base
    }

    var body: some View {
        Button {
            manager.activateHost(of: session)
        } label: {
            HStack(spacing: 10) {
                agentLogo
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    ZStack {
                        if session.status == .running || session.status == .waiting {
                            Circle()
                                .fill(session.status.color.opacity(pulse ? 0.0 : 0.45))
                                .frame(width: 12, height: 12)
                                .scaleEffect(pulse ? 1.35 : 0.7)
                        }
                        Circle()
                            .fill(session.status.color)
                            .frame(width: 7, height: 7)
                    }
                    .frame(width: 12, height: 12)

                    Text(formatElapsed(since: session.startedAt, now: now))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if session.status == .running || session.status == .waiting {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
        .onChange(of: session.status) { _, newStatus in
            if newStatus == .running || newStatus == .waiting {
                pulse = false
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    pulse = false
                }
            }
        }
    }

    @ViewBuilder
    private var agentLogo: some View {
        let _ = iconProvider.revision
        if let nsImage = iconProvider.icon(for: session.agentID) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
