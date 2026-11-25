import Foundation

public enum HookConfigMerger {
    public static let marker = "/.mynotch/bin/notch-report"
    public static let antigravityHookKey = "mynotch-agent-monitor"

    private static let antigravityGroupedEvents: Set<String> = ["PreToolUse", "PostToolUse"]

    public static func installing(
        into config: JSONValue,
        agentID: String,
        events: [String],
        reporterPath: String,
        format: String = "claude"
    ) -> JSONValue {
        if format == "antigravity" {
            return installingAntigravity(
                into: config,
                agentID: agentID,
                events: events,
                reporterPath: reporterPath
            )
        }
        return installingClaude(
            into: config,
            agentID: agentID,
            events: events,
            reporterPath: reporterPath
        )
    }

    public static func uninstalling(from config: JSONValue, format: String = "claude") -> JSONValue {
        if format == "antigravity" {
            return uninstallingAntigravity(from: config)
        }
        return uninstallingClaude(from: config)
    }

    public static func isInstalled(
        in config: JSONValue,
        events: [String],
        format: String = "claude"
    ) -> Bool {
        if format == "antigravity" {
            return isInstalledAntigravity(in: config, events: events)
        }
        return isInstalledClaude(in: config, events: events)
    }

    // MARK: - Claude / Codex format

    private static func installingClaude(
        into config: JSONValue,
        agentID: String,
        events: [String],
        reporterPath: String
    ) -> JSONValue {
        var root = config.objectValue ?? [:]
        var hooks = root["hooks"]?.objectValue ?? [:]

        for event in events {
            var groups = hooks[event]?.arrayValue ?? []
            if groups.contains(where: isOwnGroup) {
                continue
            }

            let entry = JSONValue.object([
                "matcher": .string(".*"),
                "hooks": .array([
                    .object([
                        "type": .string("command"),
                        "command": .string("\(reporterPath) \(agentID) \(event)"),
                        "timeout": .number(5)
                    ])
                ])
            ])
            groups.append(entry)
            hooks[event] = .array(groups)
        }

        root["hooks"] = .object(hooks)
        return .object(root)
    }

    private static func uninstallingClaude(from config: JSONValue) -> JSONValue {
        guard var root = config.objectValue,
              let hooks = root["hooks"]?.objectValue
        else {
            return config
        }

        var nextHooks: [String: JSONValue] = [:]
        for (event, value) in hooks {
            guard let groups = value.arrayValue else {
                nextHooks[event] = value
                continue
            }
            let remaining = groups.filter { !isOwnGroup($0) }
            if !remaining.isEmpty {
                nextHooks[event] = .array(remaining)
            }
        }

        if nextHooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = .object(nextHooks)
        }

        return .object(root)
    }

    private static func isInstalledClaude(in config: JSONValue, events: [String]) -> Bool {
        guard !events.isEmpty,
              let hooks = config["hooks"]?.objectValue
        else {
            return false
        }

        return events.allSatisfy { event in
            guard let groups = hooks[event]?.arrayValue else { return false }
            return groups.contains(where: isOwnGroup)
        }
    }

    // MARK: - Antigravity format

    private static func installingAntigravity(
        into config: JSONValue,
        agentID: String,
        events: [String],
        reporterPath: String
    ) -> JSONValue {
        var root = config.objectValue ?? [:]
        var section = root[antigravityHookKey]?.objectValue ?? [:]

        for event in events {
            var list = section[event]?.arrayValue ?? []
            let handler = JSONValue.object([
                "type": .string("command"),
                "command": .string("\(reporterPath) \(agentID) \(event) && printf '{}'"),
                "timeout": .number(5)
            ])

            if antigravityGroupedEvents.contains(event) {
                if list.contains(where: isOwnGroup) {
                    continue
                }
                list.append(JSONValue.object([
                    "matcher": .string("*"),
                    "hooks": .array([handler])
                ]))
            } else {
                if list.contains(where: isOwnHandler) {
                    continue
                }
                list.append(handler)
            }

            section[event] = .array(list)
        }

        root[antigravityHookKey] = .object(section)
        return .object(root)
    }

    private static func uninstallingAntigravity(from config: JSONValue) -> JSONValue {
        guard var root = config.objectValue else {
            return config
        }
        root.removeValue(forKey: antigravityHookKey)
        return .object(root)
    }

    private static func isInstalledAntigravity(in config: JSONValue, events: [String]) -> Bool {
        guard !events.isEmpty,
              let section = config[antigravityHookKey]?.objectValue
        else {
            return false
        }

        return events.allSatisfy { event in
            guard let list = section[event]?.arrayValue else { return false }
            if antigravityGroupedEvents.contains(event) {
                return list.contains(where: isOwnGroup)
            }
            return list.contains(where: isOwnHandler)
        }
    }

    private static func isOwnGroup(_ group: JSONValue) -> Bool {
        guard let entries = group["hooks"]?.arrayValue else { return false }
        return entries.contains(where: isOwnHandler)
    }

    private static func isOwnHandler(_ handler: JSONValue) -> Bool {
        guard let command = handler["command"]?.stringValue else { return false }
        return command.contains(marker)
    }
}
