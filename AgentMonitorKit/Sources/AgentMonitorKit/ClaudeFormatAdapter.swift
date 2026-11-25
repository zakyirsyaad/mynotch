import Foundation

public enum ClaudeFormatAdapter {
    public static func adapt(_ event: InboxEvent) -> AgentEvent? {
        let rawEventName = event.event.isEmpty
            ? (event.payload["hook_event_name"]?.stringValue ?? "")
            : event.event

        guard let kind = mapKind(eventName: rawEventName, payload: event.payload) else {
            return nil
        }

        let rawSessionID = event.payload["session_id"]?.stringValue
        let sessionID = (rawSessionID?.isEmpty == false)
            ? rawSessionID!
            : "\(event.source)-\(event.pid)"

        let cwdName = extractCwdName(from: event.payload["cwd"]?.stringValue)

        return AgentEvent(
            sessionID: sessionID,
            agentID: event.source,
            pid: event.pid,
            cwdName: cwdName,
            kind: kind,
            at: event.timestamp
        )
    }

    private static func mapKind(eventName: String, payload: JSONValue) -> AgentEventKind? {
        switch eventName {
        case "SessionStart", "UserPromptSubmit", "PostToolUse":
            return .status(.running, detail: nil)
        case "Notification":
            let detail = cleanedDetail(payload["message"]?.stringValue)
            return .status(.waiting, detail: detail)
        case "PermissionRequest":
            let detail: String?
            if let toolName = nonEmpty(payload["tool_name"]?.stringValue) {
                detail = TextTruncation.detail("Izinkan \(toolName)?")
            } else {
                detail = cleanedDetail(payload["message"]?.stringValue)
            }
            return .status(.waiting, detail: detail)
        case "Stop":
            return .status(.done, detail: nil)
        case "StopFailure":
            let detail = cleanedDetail(payload["error"]?.stringValue)
                ?? cleanedDetail(payload["message"]?.stringValue)
            return .status(.error, detail: detail)
        case "SubagentStart":
            return .subagentStarted
        case "SubagentStop":
            return .subagentStopped
        case "SessionEnd":
            return .sessionEnded
        default:
            return nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanedDetail(_ value: String?) -> String? {
        guard let value else { return nil }
        let truncated = TextTruncation.detail(value)
        return truncated.isEmpty ? nil : truncated
    }

    private static func extractCwdName(from cwd: String?) -> String? {
        guard let cwd = nonEmpty(cwd), cwd != "/" else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
