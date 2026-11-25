import Foundation
import Testing
@testable import AgentMonitorKit

private let reporterPath = "/Users/test/.mynotch/bin/notch-report"

private func decodeJSON(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private extension Optional where Wrapped == JSONValue {
    var arrayCount: Int? {
        self?.arrayValue?.count
    }
}

@Test func installIntoEmptyObject() {
    let out = HookConfigMerger.installing(into: .object([:]), agentID: "codex", events: ["Stop"], reporterPath: reporterPath)
    #expect(out["hooks"]?["Stop"]?.arrayCount == 1)
    #expect(HookConfigMerger.isInstalled(in: out, events: ["Stop"]))
}

@Test func installPreservesForeignHooks() throws {
    let existing = try decodeJSON(#"{"model":"x","hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"other"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[]}]}}"#)
    let out = HookConfigMerger.installing(into: existing, agentID: "codex", events: ["Stop"], reporterPath: reporterPath)
    #expect(out["model"] == .string("x"))
    #expect(out["hooks"]?["Stop"]?.arrayCount == 2)
    #expect(out["hooks"]?["PreToolUse"] == existing["hooks"]?["PreToolUse"])
}

@Test func installIsIdempotent() {
    let once = HookConfigMerger.installing(into: .object([:]), agentID: "codex", events: ["Stop"], reporterPath: reporterPath)
    #expect(HookConfigMerger.installing(into: once, agentID: "codex", events: ["Stop"], reporterPath: reporterPath) == once)
}

@Test func uninstallRemovesOnlyOwnEntries() throws {
    let existing = try decodeJSON(#"{"hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"other"}]}]}}"#)
    let installed = HookConfigMerger.installing(into: existing, agentID: "codex", events: ["Stop", "SessionStart"], reporterPath: reporterPath)
    #expect(HookConfigMerger.uninstalling(from: installed) == existing)
}

@Test func uninstallCleansEmptyHooksObject() {
    let installed = HookConfigMerger.installing(into: .object([:]), agentID: "codex", events: ["Stop"], reporterPath: reporterPath)
    #expect(HookConfigMerger.uninstalling(from: installed) == .object([:]))
}

@Test func partialInstallIsNotInstalled() {
    let out = HookConfigMerger.installing(into: .object([:]), agentID: "codex", events: ["Stop"], reporterPath: reporterPath)
    #expect(!HookConfigMerger.isInstalled(in: out, events: ["Stop", "SessionStart"]))
    #expect(!HookConfigMerger.isInstalled(in: .object([:]), events: []))
}
