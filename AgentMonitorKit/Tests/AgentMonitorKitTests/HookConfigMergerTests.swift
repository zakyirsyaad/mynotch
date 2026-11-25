import Foundation
import Testing
@testable import AgentMonitorKit

private let reporterPath = "/Users/test/.mynotch/bin/notch-report"

private func decodeJSON(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private extension JSONValue {
    var arrayCount: Int? {
        arrayValue?.count
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

@Test func antigravityInstallPreservesForeignHooksAndUninstallsCleanly() throws {
    let existing = try decodeJSON(#"{"ecc-session-init":{"SessionStart":[{"type":"command","command":"node init.js"}]}}"#)
    let events = ["SessionStart", "PreInvocation", "PostToolUse", "Stop"]
    let installed = HookConfigMerger.installing(
        into: existing,
        agentID: "antigravity",
        events: events,
        reporterPath: reporterPath,
        format: "antigravity"
    )
    #expect(installed["ecc-session-init"] == existing["ecc-session-init"])
    #expect(HookConfigMerger.isInstalled(in: installed, events: events, format: "antigravity"))
    #expect(installed[HookConfigMerger.antigravityHookKey]?["SessionStart"]?.arrayValue?.first?["command"]?.stringValue?.hasSuffix("&& printf '{}'") == true)
    #expect(installed[HookConfigMerger.antigravityHookKey]?["PostToolUse"]?.arrayValue?.first?["matcher"] == .string("*"))
    #expect(HookConfigMerger.installing(into: installed, agentID: "antigravity", events: events, reporterPath: reporterPath, format: "antigravity") == installed)

    let uninstalled = HookConfigMerger.uninstalling(from: installed, format: "antigravity")
    #expect(uninstalled == existing)
    #expect(!HookConfigMerger.isInstalled(in: uninstalled, events: events, format: "antigravity"))
}
