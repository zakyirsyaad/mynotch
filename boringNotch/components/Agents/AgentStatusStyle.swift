import AgentMonitorKit
import SwiftUI

extension AgentStatus {
    var color: Color {
        switch self {
        case .waiting: return .orange
        case .error: return .red
        case .running: return .teal
        case .done: return .green
        }
    }

    var label: String {
        switch self {
        case .waiting: return "Butuh input"
        case .error: return "Error"
        case .running: return "Berjalan"
        case .done: return "Selesai"
        }
    }
}

func formatElapsed(since: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(since)))
    if seconds < 60 {
        return "<1 mnt"
    }
    let minutes = seconds / 60
    if minutes < 60 {
        return "\(minutes) mnt"
    }
    let hours = minutes / 60
    return "\(hours) jam"
}
