import Foundation

public enum AgentStatus: String, Sendable, Codable, CaseIterable {
    case waiting
    case error
    case running
    case done

    public var sortRank: Int {
        switch self {
        case .waiting: return 0
        case .error: return 1
        case .running: return 2
        case .done: return 3
        }
    }
}

public enum SessionOrigin: String, Sendable, Equatable, Codable {
    case hooks
    case process
}

public struct AgentSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let agentID: String
    public let pid: Int32
    public let cwdName: String?
    public let status: AgentStatus
    public let detail: String?
    public let subagentCount: Int
    public let startedAt: Date
    public let updatedAt: Date
    public let origin: SessionOrigin

    public init(
        id: String,
        agentID: String,
        pid: Int32,
        cwdName: String?,
        status: AgentStatus,
        detail: String?,
        subagentCount: Int,
        startedAt: Date,
        updatedAt: Date,
        origin: SessionOrigin
    ) {
        self.id = id
        self.agentID = agentID
        self.pid = pid
        self.cwdName = cwdName
        self.status = status
        self.detail = detail
        self.subagentCount = subagentCount
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.origin = origin
    }
}

public enum AgentEventKind: Sendable, Equatable {
    case status(AgentStatus, detail: String?)
    case subagentStarted
    case subagentStopped
    case sessionEnded
}

public struct AgentEvent: Sendable, Equatable {
    public let sessionID: String
    public let agentID: String
    public let pid: Int32
    public let cwdName: String?
    public let kind: AgentEventKind
    public let at: Date

    public init(
        sessionID: String,
        agentID: String,
        pid: Int32,
        cwdName: String?,
        kind: AgentEventKind,
        at: Date
    ) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.pid = pid
        self.cwdName = cwdName
        self.kind = kind
        self.at = at
    }
}

public struct ScannedProcess: Sendable, Equatable {
    public let pid: Int32
    public let agentID: String
    public let startedAt: Date

    public init(pid: Int32, agentID: String, startedAt: Date) {
        self.pid = pid
        self.agentID = agentID
        self.startedAt = startedAt
    }
}
