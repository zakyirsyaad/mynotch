import Foundation

public enum HookConfigMerger {
    public static let marker = "/.mynotch/bin/notch-report"

    public static func installing(
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

    public static func uninstalling(from config: JSONValue) -> JSONValue {
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

    public static func isInstalled(in config: JSONValue, events: [String]) -> Bool {
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

    private static func isOwnGroup(_ group: JSONValue) -> Bool {
        guard let entries = group["hooks"]?.arrayValue else { return false }
        return entries.contains { entry in
            guard let command = entry["command"]?.stringValue else { return false }
            return command.contains(marker)
        }
    }
}
