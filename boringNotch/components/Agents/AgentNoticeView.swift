import AgentMonitorKit
import SwiftUI

struct AgentNoticeView: View {
    let notice: AgentNotice

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var iconProvider = AgentIconProvider.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var innerWidth: CGFloat {
        max(320, agentNoticeWidth - (cornerRadiusInsets.closed.bottom * 2))
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                noticeLogo
                    .frame(width: 16, height: 16)

                Text(notice.title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: (appeared || reduceMotion) ? 0 : -10)
            .opacity((appeared || reduceMotion) ? 1 : 0)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 5) {
                Circle()
                    .fill(notice.status.color)
                    .frame(width: 7, height: 7)

                Text(notice.status.label)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(x: (appeared || reduceMotion) ? 0 : 10)
            .opacity((appeared || reduceMotion) ? 1 : 0)
        }
        .frame(width: innerWidth, height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                    appeared = true
                }
            }
        }
    }

    @ViewBuilder
    private var noticeLogo: some View {
        let _ = iconProvider.revision
        if let nsImage = iconProvider.icon(for: notice.agentID) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}
