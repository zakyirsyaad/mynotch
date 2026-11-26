import AgentMonitorKit
import SwiftUI

struct AgentsTabView: View {
    @ObservedObject private var manager = AgentMonitorManager.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            if manager.sessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Tidak ada agent yang berjalan")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(manager.sessions.count) agent")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            ForEach(manager.sessions) { session in
                                AgentRowView(session: session, now: context.date)
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .top)
                                                .combined(with: .opacity)
                                                .combined(with: .scale(scale: 0.96)),
                                            removal: .opacity.combined(with: .scale(scale: 0.96))
                                        )
                                    )
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: manager.sessions)
        .onAppear {
            manager.refreshNow()
        }
    }
}
