import AgentMonitorKit
import SwiftUI

struct AgentRowView: View {
    let session: AgentSession
    let now: Date

    @ObservedObject private var manager = AgentMonitorManager.shared
    @ObservedObject private var iconProvider = AgentIconProvider.shared

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
                    Circle()
                        .fill(session.status.color)
                        .frame(width: 7, height: 7)

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
