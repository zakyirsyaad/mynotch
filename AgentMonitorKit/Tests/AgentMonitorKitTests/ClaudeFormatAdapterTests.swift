import Foundation
import Testing
@testable import AgentMonitorKit

@Test func notificationBecomesWaitingWithMessage() throws {
    let e = try #require(ClaudeFormatAdapter.adapt(fixture("claude-code", "Notification")))
    guard case .status(.waiting, let detail) = e.kind else {
        Issue.record("bukan waiting")
        return
    }
    #expect(detail?.isEmpty == false)
    #expect(e.agentID == "claude-code")
}

@Test func codexPermissionRequestBecomesWaiting() throws {
    let e = try #require(ClaudeFormatAdapter.adapt(fixture("codex", "PermissionRequest")))
    guard case .status(.waiting, let detail) = e.kind else {
        Issue.record("bukan waiting")
        return
    }
    #expect(detail?.hasPrefix("Izinkan ") == true)
}

@Test(arguments: ["SessionStart", "UserPromptSubmit", "PostToolUse"])
func runningEvents(name: String) throws {
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", name))?.kind == .status(.running, detail: nil))
    #expect(try ClaudeFormatAdapter.adapt(fixture("codex", name))?.kind == .status(.running, detail: nil))
}

@Test func stopBecomesDone() throws {
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", "Stop"))?.kind == .status(.done, detail: nil))
    #expect(try ClaudeFormatAdapter.adapt(fixture("codex", "Stop"))?.kind == .status(.done, detail: nil))
}

@Test func stopFailureBecomesError() throws {
    let e = try #require(ClaudeFormatAdapter.adapt(fixture("claude-code", "StopFailure")))
    guard case .status(.error, let detail) = e.kind else {
        Issue.record("bukan error")
        return
    }
    #expect(detail == "API rate limit exceeded")
}

@Test func subagentEventsMapCorrectly() throws {
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", "SubagentStart"))?.kind == .subagentStarted)
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", "SubagentStop"))?.kind == .subagentStopped)
    #expect(try ClaudeFormatAdapter.adapt(fixture("codex", "SubagentStop"))?.kind == .subagentStopped)
}

@Test func sessionEndEndsSession() throws {
    #expect(try ClaudeFormatAdapter.adapt(fixture("claude-code", "SessionEnd"))?.kind == .sessionEnded)
}

@Test func cwdNameIsLastPathComponent() throws {
    let stop = try fixture("claude-code", "Stop")
    #expect(ClaudeFormatAdapter.adapt(stop)?.cwdName == URL(fileURLWithPath: stop.payload["cwd"]!.stringValue!).lastPathComponent)
}

@Test func unknownEventIgnored() {
    let e = InboxEvent(
        version: 1,
        source: "claude-code",
        event: "PreCompact",
        pid: 1,
        timestamp: .now,
        payload: .object(["session_id": .string("s")])
    )
    #expect(ClaudeFormatAdapter.adapt(e) == nil)
}

@Test func missingSessionIdFallsBackToSourceAndPid() {
    let e = InboxEvent(version: 1, source: "codex", event: "Stop", pid: 77, timestamp: .now, payload: .null)
    #expect(ClaudeFormatAdapter.adapt(e)?.sessionID == "codex-77")
}

@Test func detailCollapsesNewlinesAndTruncatesGraphemes() {
    let text = "Izinkan\nBash:\n" + String(repeating: "👩‍💻", count: 100)
    let out = TextTruncation.detail(text)
    #expect(!out.contains("\n"))
    #expect(out.count == 80)
    #expect(out.hasSuffix("…"))
}

@Test func detailPreservesShortTextAndHandlesEdgeLimits() {
    #expect(TextTruncation.detail("  Halo\n\tdunia  ") == "Halo dunia")
    #expect(TextTruncation.detail("abc", limit: 0) == "")
    #expect(TextTruncation.detail("abc", limit: 1) == "…")
}

@Test func antigravityCamelCasePayloadMapsPreInvocationAndStop() throws {
    let pre = InboxEvent(
        version: 1,
        source: "antigravity",
        event: "",
        pid: 13628,
        timestamp: .now,
        payload: .object([
            "conversationId": .string("conv-42"),
            "workspacePaths": .array([.string("/Users/test/projects/mynotch")]),
            "hookEventName": .string("PreInvocation"),
            "lastUserInput": .string("secret prompt")
        ])
    )
    let adaptedPre = try #require(ClaudeFormatAdapter.adapt(pre))
    #expect(adaptedPre.sessionID == "conv-42")
    #expect(adaptedPre.cwdName == "mynotch")
    #expect(adaptedPre.kind == .status(.running, detail: nil))

    let stop = InboxEvent(
        version: 1,
        source: "antigravity",
        event: "Stop",
        pid: 13628,
        timestamp: .now,
        payload: .object([
            "conversationId": .string("conv-42"),
            "cwd": .string("/Users/test/projects/mynotch")
        ])
    )
    #expect(ClaudeFormatAdapter.adapt(stop)?.kind == .status(.done, detail: nil))
}
