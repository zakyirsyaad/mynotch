import Foundation
import Testing
@testable import AgentMonitorKit

private func snap(
    _ pid: Int32,
    _ exe: String,
    _ args: [String] = [],
    ppid: Int32 = 1
) -> ProcessSnapshot {
    ProcessSnapshot(pid: pid, ppid: ppid, executable: exe, arguments: args, startedAt: .distantPast)
}

@Test func exactExecutableMatches() throws {
    let reg = try AgentRegistry.bundled()
    #expect(ProcessMatcher.agentID(for: snap(1, "claude"), in: reg) == "claude-code")
    #expect(ProcessMatcher.agentID(for: snap(2, "codex"), in: reg) == "codex")
    #expect(ProcessMatcher.agentID(for: snap(3, "Antigravity"), in: reg) == "antigravity")
    #expect(ProcessMatcher.agentID(for: snap(4, "agy"), in: reg) == "antigravity")
}

@Test func matchIsCaseSensitive() throws {
    let reg = try AgentRegistry.bundled()
    #expect(ProcessMatcher.agentID(for: snap(1, "Claude"), in: reg) == nil)
}

@Test func interpreterMatchesByArgumentBasename() throws {
    let reg = try AgentRegistry.bundled()
    #expect(ProcessMatcher.agentID(for: snap(1, "node", ["node", "/opt/homebrew/bin/gemini"]), in: reg) == "gemini-cli")
}

@Test func nonInterpreterIgnoresArguments() throws {
    let reg = try AgentRegistry.bundled()
    #expect(ProcessMatcher.agentID(for: snap(1, "vim", ["vim", "gemini"]), in: reg) == nil)
}

@Test func customRuleMatches() throws {
    let reg = try AgentRegistry.bundled()
    let r = reg.adding([CustomAgentRule(id: "myagent", displayName: "myagent", executable: "myagent")])
    #expect(ProcessMatcher.agentID(for: snap(1, "myagent"), in: r) == "myagent")
}

@Test func scanExtractsMatchingProcesses() throws {
    let reg = try AgentRegistry.bundled()
    let scanned = ProcessMatcher.scan([snap(10, "claude"), snap(11, "zsh")], in: reg)
    #expect(scanned == [ScannedProcess(pid: 10, agentID: "claude-code", startedAt: .distantPast)])
}

@Test func ancestorsStopAtMaxDepth() {
    let lookup: (Int32) -> ProcessSnapshot? = { pid in snap(pid, "sh", ppid: pid + 1) }
    #expect(ProcessMatcher.ancestors(of: 1, lookup: lookup).count == 16)
}

@Test func resolveAgentPidWalksPastShell() throws {
    let reg = try AgentRegistry.bundled()
    let table = [
        100: snap(100, "sh", ppid: 50),
        50: snap(50, "claude", ppid: 10),
        10: snap(10, "Terminal", ppid: 1)
    ]
    #expect(ProcessMatcher.resolveAgentPID(from: 100, agentID: "claude-code", lookup: { table[Int($0)] }, in: reg) == 50)
}

@Test func resolveFallsBackToOriginalPid() throws {
    let reg = try AgentRegistry.bundled()
    #expect(ProcessMatcher.resolveAgentPID(from: 100, agentID: "claude-code", lookup: { _ in nil }, in: reg) == 100)
}
