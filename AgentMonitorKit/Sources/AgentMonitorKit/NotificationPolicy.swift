import Foundation

public struct NotifySettings: Sendable, Equatable {
    public let waiting: Bool
    public let error: Bool
    public let done: Bool

    public init(waiting: Bool, error: Bool, done: Bool) {
        self.waiting = waiting
        self.error = error
        self.done = done
    }
}

public struct NoticeContext: Sendable, Equatable {
    public let frontmostBundleID: String?
    public let hostBundleID: String?
    public let notchOpen: Bool
    public let hiddenForFullscreen: Bool

    public init(
        frontmostBundleID: String?,
        hostBundleID: String?,
        notchOpen: Bool,
        hiddenForFullscreen: Bool
    ) {
        self.frontmostBundleID = frontmostBundleID
        self.hostBundleID = hostBundleID
        self.notchOpen = notchOpen
        self.hiddenForFullscreen = hiddenForFullscreen
    }
}

public struct AgentNotice: Sendable, Equatable, Identifiable {
    public let id: String
    public let agentID: String
    public let title: String
    public let status: AgentStatus
    public let duration: TimeInterval

    public init(
        id: String,
        agentID: String,
        title: String,
        status: AgentStatus,
        duration: TimeInterval
    ) {
        self.id = id
        self.agentID = agentID
        self.title = title
        self.status = status
        self.duration = duration
    }
}

public enum NotificationPolicy {
    public static func notice(
        for change: StatusChange,
        displayName: String,
        settings: NotifySettings,
        context: NoticeContext
    ) -> AgentNotice? {
        guard !context.notchOpen, !context.hiddenForFullscreen else {
            return nil
        }

        if let host = context.hostBundleID, host == context.frontmostBundleID {
            return nil
        }

        let duration: TimeInterval
        switch change.to {
        case .waiting:
            guard settings.waiting else { return nil }
            duration = 5
        case .error:
            guard settings.error else { return nil }
            duration = 3
        case .done:
            guard settings.done else { return nil }
            duration = 3
        case .running:
            return nil
        }

        let title: String
        if let cwdName = change.session.cwdName, !cwdName.isEmpty {
            title = "\(displayName) · \(cwdName)"
        } else {
            title = displayName
        }

        return AgentNotice(
            id: change.session.id,
            agentID: change.session.agentID,
            title: title,
            status: change.to,
            duration: duration
        )
    }
}

public struct NoticeQueue: Sendable, Equatable {
    public let pending: [AgentNotice]

    public init(pending: [AgentNotice] = []) {
        self.pending = pending
    }

    public func enqueuing(_ notice: AgentNotice) -> NoticeQueue {
        var next = pending
        if let index = next.firstIndex(where: { $0.id == notice.id }) {
            next[index] = notice
        } else {
            next.append(notice)
        }
        return NoticeQueue(pending: next)
    }

    public func dequeued() -> (notice: AgentNotice?, queue: NoticeQueue) {
        guard let first = pending.first else {
            return (nil, self)
        }
        return (first, NoticeQueue(pending: Array(pending.dropFirst())))
    }
}
