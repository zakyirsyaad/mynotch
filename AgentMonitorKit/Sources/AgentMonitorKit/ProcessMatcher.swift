import Foundation

public struct ProcessSnapshot: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let executable: String
    public let arguments: [String]
    public let startedAt: Date

    public init(
        pid: Int32,
        ppid: Int32,
        executable: String,
        arguments: [String],
        startedAt: Date
    ) {
        self.pid = pid
        self.ppid = ppid
        self.executable = executable
        self.arguments = arguments
        self.startedAt = startedAt
    }
}

public enum ProcessMatcher {
    public static let interpreters: Set<String> = ["node", "bun", "python3", "python"]

    public static func agentID(for process: ProcessSnapshot, in registry: AgentRegistry) -> String? {
        for def in registry.definitions {
            if def.match.executable.contains(process.executable) {
                return def.id
            }
        }

        guard interpreters.contains(process.executable), !process.arguments.isEmpty else {
            return nil
        }

        let argBasenames = Set(
            process.arguments
                .dropFirst()
                .map { URL(fileURLWithPath: $0).lastPathComponent }
        )

        for def in registry.definitions where !def.match.argvContains.isEmpty {
            if def.match.argvContains.contains(where: { argBasenames.contains($0) }) {
                return def.id
            }
        }

        return nil
    }

    public static func scan(_ processes: [ProcessSnapshot], in registry: AgentRegistry) -> [ScannedProcess] {
        processes.compactMap { process in
            guard let id = agentID(for: process, in: registry) else { return nil }
            return ScannedProcess(pid: process.pid, agentID: id, startedAt: process.startedAt)
        }
    }

    public static func ancestors(
        of pid: Int32,
        lookup: (Int32) -> ProcessSnapshot?,
        maxDepth: Int = 16
    ) -> [ProcessSnapshot] {
        guard maxDepth > 0 else { return [] }

        var result: [ProcessSnapshot] = []
        var visited: Set<Int32> = []
        var currentPID = pid

        while result.count < maxDepth, !visited.contains(currentPID) {
            visited.insert(currentPID)
            guard let snap = lookup(currentPID) else { break }
            result.append(snap)
            if snap.ppid <= 1 || snap.ppid == currentPID {
                break
            }
            currentPID = snap.ppid
        }

        return result
    }

    public static func resolveAgentPID(
        from pid: Int32,
        agentID: String,
        lookup: (Int32) -> ProcessSnapshot?,
        in registry: AgentRegistry
    ) -> Int32 {
        for snap in ancestors(of: pid, lookup: lookup) {
            if self.agentID(for: snap, in: registry) == agentID {
                return snap.pid
            }
        }
        return pid
    }
}
