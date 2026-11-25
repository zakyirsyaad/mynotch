import Foundation
import Testing
@testable import AgentMonitorKit

private let allSettings = NotifySettings(waiting: true, error: true, done: true)
private let calmContext = NoticeContext(
    frontmostBundleID: "com.apple.Safari",
    hostBundleID: "com.anthropic.claudefordesktop",
    notchOpen: false,
    hiddenForFullscreen: false
)

private func change(to status: AgentStatus, cwd: String? = "mynotch") -> StatusChange {
    let session = AgentSession(
        id: "s1",
        agentID: "claude-code",
        pid: 10,
        cwdName: cwd,
        status: status,
        detail: nil,
        subagentCount: 0,
        startedAt: .distantPast,
        updatedAt: .now,
        origin: .hooks
    )
    return StatusChange(session: session, from: .running, to: status)
}

private func makeNotice(_ id: String, _ status: AgentStatus) -> AgentNotice {
    AgentNotice(id: id, agentID: "claude-code", title: id, status: status, duration: 3)
}

@Test func waitingShowsFiveSeconds() {
    let n = NotificationPolicy.notice(
        for: change(to: .waiting, cwd: "mynotch"),
        displayName: "Claude Code",
        settings: allSettings,
        context: calmContext
    )
    #expect(n?.duration == 5)
    #expect(n?.title == "Claude Code · mynotch")
}

@Test(arguments: [AgentStatus.error, .done])
func errorAndDoneShowThreeSeconds(status: AgentStatus) {
    #expect(
        NotificationPolicy.notice(
            for: change(to: status),
            displayName: "Codex",
            settings: allSettings,
            context: calmContext
        )?.duration == 3
    )
}

@Test func runningNeverNotifies() {
    #expect(
        NotificationPolicy.notice(
            for: change(to: .running),
            displayName: "x",
            settings: allSettings,
            context: calmContext
        ) == nil
    )
}

@Test func titleWithoutCwdIsDisplayNameOnly() {
    #expect(
        NotificationPolicy.notice(
            for: change(to: .done, cwd: nil),
            displayName: "aider",
            settings: allSettings,
            context: calmContext
        )?.title == "aider"
    )
}

@Test func suppressedWhenHostFrontmost() {
    let ctx = NoticeContext(
        frontmostBundleID: "com.anthropic.claudefordesktop",
        hostBundleID: "com.anthropic.claudefordesktop",
        notchOpen: false,
        hiddenForFullscreen: false
    )
    #expect(
        NotificationPolicy.notice(
            for: change(to: .waiting),
            displayName: "x",
            settings: allSettings,
            context: ctx
        ) == nil
    )
}

@Test func suppressedWhenNotchOpenOrFullscreen() {
    let open = NoticeContext(frontmostBundleID: nil, hostBundleID: nil, notchOpen: true, hiddenForFullscreen: false)
    let full = NoticeContext(frontmostBundleID: nil, hostBundleID: nil, notchOpen: false, hiddenForFullscreen: true)
    #expect(NotificationPolicy.notice(for: change(to: .waiting), displayName: "x", settings: allSettings, context: open) == nil)
    #expect(NotificationPolicy.notice(for: change(to: .waiting), displayName: "x", settings: allSettings, context: full) == nil)
}

@Test func respectsPerStatusSetting() {
    let noWaiting = NotifySettings(waiting: false, error: true, done: true)
    let noError = NotifySettings(waiting: true, error: false, done: true)
    let noDone = NotifySettings(waiting: true, error: true, done: false)
    #expect(NotificationPolicy.notice(for: change(to: .waiting), displayName: "x", settings: noWaiting, context: calmContext) == nil)
    #expect(NotificationPolicy.notice(for: change(to: .error), displayName: "x", settings: noError, context: calmContext) == nil)
    #expect(NotificationPolicy.notice(for: change(to: .done), displayName: "x", settings: noDone, context: calmContext) == nil)
}

@Test func queueReplacesPendingFromSameSession() {
    let q = NoticeQueue()
        .enqueuing(makeNotice("a", .running))
        .enqueuing(makeNotice("b", .done))
        .enqueuing(makeNotice("a", .waiting))
    #expect(q.pending.map(\.id) == ["a", "b"])
    #expect(q.pending.first?.status == .waiting)
}

@Test func dequeueIsFifoAndEmptyReturnsNil() {
    let (first, rest) = NoticeQueue()
        .enqueuing(makeNotice("a", .done))
        .enqueuing(makeNotice("b", .done))
        .dequeued()
    #expect(first?.id == "a")
    #expect(rest.pending.map(\.id) == ["b"])

    let (emptyFirst, emptyRest) = NoticeQueue().dequeued()
    #expect(emptyFirst == nil)
    #expect(emptyRest.pending.isEmpty)
}
