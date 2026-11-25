import Foundation

public struct StatusChange: Sendable, Equatable {
    public let session: AgentSession
    public let from: AgentStatus?
    public let to: AgentStatus

    public init(session: AgentSession, from: AgentStatus?, to: AgentStatus) {
        self.session = session
        self.from = from
        self.to = to
    }
}

public struct AgentState: Sendable, Equatable {
    public let sessions: [String: AgentSession]

    public init(sessions: [String: AgentSession] = [:]) {
        self.sessions = sessions
    }

    public func reducing(_ event: AgentEvent) -> (state: AgentState, changes: [StatusChange]) {
        var next = sessions

        // Remove any process-only placeholder for the same PID once hooks report for it.
        let procID = Self.processSessionID(pid: event.pid)
        if event.sessionID != procID, next[procID]?.origin == .process {
            next.removeValue(forKey: procID)
        }

        let existing = next[event.sessionID]

        switch event.kind {
        case .sessionEnded:
            next.removeValue(forKey: event.sessionID)
            return (AgentState(sessions: next), [])

        case .subagentStarted:
            let updated: AgentSession
            var changes: [StatusChange] = []
            if let existing {
                updated = AgentSession(
                    id: existing.id,
                    agentID: existing.agentID,
                    pid: event.pid,
                    cwdName: event.cwdName ?? existing.cwdName,
                    status: existing.status,
                    detail: existing.detail,
                    subagentCount: existing.subagentCount + 1,
                    startedAt: existing.startedAt,
                    updatedAt: event.at,
                    origin: .hooks
                )
            } else {
                updated = AgentSession(
                    id: event.sessionID,
                    agentID: event.agentID,
                    pid: event.pid,
                    cwdName: event.cwdName,
                    status: .running,
                    detail: nil,
                    subagentCount: 1,
                    startedAt: event.at,
                    updatedAt: event.at,
                    origin: .hooks
                )
                changes.append(StatusChange(session: updated, from: nil, to: .running))
            }
            next[event.sessionID] = updated
            return (AgentState(sessions: next), changes)

        case .subagentStopped:
            guard let existing else {
                return (AgentState(sessions: next), [])
            }
            let updated = AgentSession(
                id: existing.id,
                agentID: existing.agentID,
                pid: event.pid,
                cwdName: event.cwdName ?? existing.cwdName,
                status: existing.status,
                detail: existing.detail,
                subagentCount: max(0, existing.subagentCount - 1),
                startedAt: existing.startedAt,
                updatedAt: event.at,
                origin: .hooks
            )
            next[event.sessionID] = updated
            return (AgentState(sessions: next), [])

        case .status(let newStatus, let detail):
            let updated = AgentSession(
                id: event.sessionID,
                agentID: event.agentID,
                pid: event.pid,
                cwdName: event.cwdName ?? existing?.cwdName,
                status: newStatus,
                detail: detail,
                subagentCount: existing?.subagentCount ?? 0,
                startedAt: existing?.startedAt ?? event.at,
                updatedAt: event.at,
                origin: .hooks
            )
            next[event.sessionID] = updated

            let changes: [StatusChange]
            if existing?.status != newStatus {
                changes = [StatusChange(session: updated, from: existing?.status, to: newStatus)]
            } else {
                changes = []
            }
            return (AgentState(sessions: next), changes)
        }
    }

    public func merging(scanned: [ScannedProcess], now: Date) -> AgentState {
        let scannedPIDs = Set(scanned.map(\.pid))
        var next: [String: AgentSession] = [:]

        for (id, session) in sessions {
            if session.origin == .hooks || scannedPIDs.contains(session.pid) {
                next[id] = session
            }
        }

        let ownedPIDs = Set(next.values.map(\.pid))
        for process in scanned where !ownedPIDs.contains(process.pid) {
            let id = Self.processSessionID(pid: process.pid)
            next[id] = AgentSession(
                id: id,
                agentID: process.agentID,
                pid: process.pid,
                cwdName: nil,
                status: .running,
                detail: nil,
                subagentCount: 0,
                startedAt: process.startedAt,
                updatedAt: now,
                origin: .process
            )
        }

        return AgentState(sessions: next)
    }

    public func pruning(isAlive: (Int32) -> Bool) -> AgentState {
        let filtered = sessions.filter { isAlive($0.value.pid) }
        return AgentState(sessions: filtered)
    }

    public var sortedSessions: [AgentSession] {
        sessions.values.sorted { lhs, rhs in
            if lhs.status.sortRank != rhs.status.sortRank {
                return lhs.status.sortRank < rhs.status.sortRank
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    private static func processSessionID(pid: Int32) -> String {
        "proc-\(pid)"
    }
}
