import Testing
@testable import AgentMonitorKit

@Test func bundledRegistryHasElevenAgents() throws {
    let reg = try AgentRegistry.bundled()
    #expect(reg.definitions.count == 11)
    #expect(reg.definition(id: "claude-code")?.hooks?.events.contains("Stop") == true)
    #expect(reg.definition(id: "codex")?.hooks?.config == "~/.codex/hooks.json")
    #expect(reg.definition(id: "missing") == nil)
}

@Test func addingCustomRulesAppendsWithoutOverwritingBuiltins() throws {
    let reg = try AgentRegistry.bundled()
    let extended = reg.adding([
        CustomAgentRule(id: "claude-code", displayName: "Duplicate", executable: "dup"),
        CustomAgentRule(id: "myagent", displayName: "My Agent", executable: "myagent")
    ])
    #expect(extended.definitions.count == 12)
    #expect(extended.definition(id: "claude-code")?.displayName == "Claude Code")
    #expect(extended.definition(id: "myagent")?.match.executable == ["myagent"])
}
