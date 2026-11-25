import Foundation
import Testing
@testable import AgentMonitorKit

private func ev(
    _ session: String,
    _ kind: AgentEventKind,
    pid: Int32 = 10,
    at: TimeInterval = 0,
    cwdName: String? = "mynotch"
) -> AgentEvent {
    AgentEvent(
        sessionID: session,
        agentID: "claude-code",
        pid: pid,
        cwdName: cwdName,
        kind: kind,
        at: Date(timeIntervalSince1970: at)
    )
}

@Test func startCreatesRunningSession() {
    let (s, changes) = AgentState().reducing(ev("a", .status(.running, detail: nil)))
    #expect(s.sessions["a"]?.status == .running)
    #expect(s.sessions["a"]?.origin == .hooks)
    #expect(changes == [StatusChange(session: s.sessions["a"]!, from: nil, to: .running)])
}

@Test func unknownSessionCreatedFromAnyStatusEvent() {
    let (s, _) = AgentState().reducing(ev("late", .status(.waiting, detail: "Izinkan Bash?")))
    #expect(s.sessions["late"]?.status == .waiting)
    #expect(s.sessions["late"]?.detail == "Izinkan Bash?")
}

@Test func sameStatusProducesNoChange() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil))).state
    #expect(s1.reducing(ev("a", .status(.running, detail: nil), at: 5)).changes.isEmpty)
}

@Test func waitingClearedByRunning() {
    let s1 = AgentState().reducing(ev("a", .status(.waiting, detail: "x"))).state
    let (s2, changes) = s1.reducing(ev("a", .status(.running, detail: nil), at: 1))
    #expect(s2.sessions["a"]?.status == .running)
    #expect(s2.sessions["a"]?.detail == nil)
    #expect(changes.first?.from == .waiting)
}

@Test func startedAtKeptAcrossUpdates() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil), at: 0)).state
    let s2 = s1.reducing(ev("a", .status(.done, detail: nil), at: 60)).state
    #expect(s2.sessions["a"]?.startedAt == Date(timeIntervalSince1970: 0))
    #expect(s2.sessions["a"]?.updatedAt == Date(timeIntervalSince1970: 60))
}

@Test func sessionEndedRemoves() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil))).state
    #expect(s1.reducing(ev("a", .sessionEnded)).state.sessions["a"] == nil)
}

@Test func subagentStartIncrementsAndStopDecrementsNeverNegative() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil))).state
    let s2 = s1.reducing(ev("a", .subagentStarted, at: 1)).state
    #expect(s2.sessions["a"]?.subagentCount == 1)
    let s3 = s2.reducing(ev("a", .subagentStopped, at: 2)).state
    #expect(s3.sessions["a"]?.subagentCount == 0)
    let s4 = s3.reducing(ev("a", .subagentStopped, at: 3)).state
    #expect(s4.sessions["a"]?.subagentCount == 0)
}

@Test func twoSessionsSameCwdStaySeparate() {
    let s = AgentState()
        .reducing(ev("a", .status(.running, detail: nil), pid: 10)).state
        .reducing(ev("b", .status(.waiting, detail: nil), pid: 11)).state
    #expect(s.sessions.count == 2)
}

@Test func scanAddsProcessOnlySession() {
    let s = AgentState().merging(
        scanned: [ScannedProcess(pid: 99, agentID: "aider", startedAt: .distantPast)],
        now: .now
    )
    #expect(s.sessions.values.first?.origin == .process)
    #expect(s.sessions.values.first?.status == .running)
}

@Test func scanSkipsPidOwnedByHooksSession() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil), pid: 50)).state
    #expect(
        s1.merging(scanned: [ScannedProcess(pid: 50, agentID: "claude-code", startedAt: .distantPast)], now: .now)
            .sessions.count == 1
    )
}

@Test func hooksEventReplacesProcessPlaceholderForSamePid() {
    let s1 = AgentState().merging(
        scanned: [ScannedProcess(pid: 50, agentID: "claude-code", startedAt: .distantPast)],
        now: .now
    )
    #expect(s1.sessions["proc-50"]?.origin == .process)
    let s2 = s1.reducing(ev("sess-50", .status(.waiting, detail: "Izinkan?"), pid: 50, at: 10)).state
    #expect(s2.sessions.count == 1)
    #expect(s2.sessions["proc-50"] == nil)
    #expect(s2.sessions["sess-50"]?.origin == .hooks)
}

@Test func scanRemovesVanishedProcessSessionsOnly() {
    let s1 = AgentState()
        .reducing(ev("a", .status(.running, detail: nil), pid: 50)).state
        .merging(scanned: [ScannedProcess(pid: 99, agentID: "aider", startedAt: .distantPast)], now: .now)
    let s2 = s1.merging(scanned: [], now: .now)
    #expect(s2.sessions.count == 1)
    #expect(s2.sessions["a"] != nil)
}

@Test func pruneRemovesDeadPids() {
    let s1 = AgentState().reducing(ev("a", .status(.running, detail: nil), pid: 50)).state
    #expect(s1.pruning(isAlive: { _ in false }).sessions.isEmpty)
}

@Test func sortOrderByStatusThenRecency() {
    let s = AgentState()
        .reducing(ev("done", .status(.done, detail: nil), at: 9)).state
        .reducing(ev("run1", .status(.running, detail: nil), at: 1)).state
        .reducing(ev("run2", .status(.running, detail: nil), at: 2)).state
        .reducing(ev("err", .status(.error, detail: nil), at: 0)).state
        .reducing(ev("wait", .status(.waiting, detail: nil), at: 0)).state
    #expect(s.sortedSessions.map(\.id) == ["wait", "err", "run2", "run1", "done"])
}
