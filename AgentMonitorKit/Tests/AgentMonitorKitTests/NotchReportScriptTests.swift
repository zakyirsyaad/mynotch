import Foundation
import Testing
@testable import AgentMonitorKit

private func makeTempHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mynotch-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func inboxFiles(_ home: URL) throws -> [URL] {
    let inbox = MyNotchPaths(home: home).inbox
    guard FileManager.default.fileExists(atPath: inbox.path) else {
        return []
    }
    return try FileManager.default.contentsOfDirectory(
        at: inbox,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }
}

private func runReporter(args: [String], stdin: String, home: URL) throws -> (exitCode: Int32, stdout: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [NotchReportScript.url.path] + args
    var env = ProcessInfo.processInfo.environment
    env["HOME"] = home.path
    process.environment = env

    let inPipe = Pipe()
    let outPipe = Pipe()
    process.standardInput = inPipe
    process.standardOutput = outPipe

    try process.run()
    inPipe.fileHandleForWriting.write(Data(stdin.utf8))
    try inPipe.fileHandleForWriting.close()
    process.waitUntilExit()

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(decoding: outData, as: UTF8.self)
    return (process.terminationStatus, stdout)
}

@Test func writesEnvelopeWithPayload() throws {
    let home = try makeTempHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let result = try runReporter(args: ["claude-code", "Stop"], stdin: #"{"session_id":"s1"}"#, home: home)
    #expect(result.exitCode == 0)
    #expect(result.stdout.isEmpty)
    let files = try inboxFiles(home)
    #expect(files.count == 1)
    let event = try InboxEvent.decode(Data(contentsOf: files[0]))
    #expect(event.source == "claude-code")
    #expect(event.payload["session_id"]?.stringValue == "s1")
}

@Test func emptyStdinBecomesNull() throws {
    let home = try makeTempHome()
    defer { try? FileManager.default.removeItem(at: home) }

    _ = try runReporter(args: ["codex", "Stop"], stdin: "", home: home)
    let files = try inboxFiles(home)
    #expect(files.count == 1)
    #expect(try InboxEvent.decode(Data(contentsOf: files[0])).payload == .null)
}

@Test func invalidArgumentWritesNothing() throws {
    let home = try makeTempHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let result = try runReporter(args: [#"bad"name"#, "Stop"], stdin: "{}", home: home)
    #expect(result.exitCode == 0)
    #expect(try inboxFiles(home).isEmpty)
}

@Test func inboxCreatedPrivate() throws {
    let home = try makeTempHome()
    defer { try? FileManager.default.removeItem(at: home) }

    _ = try runReporter(args: ["codex", "Stop"], stdin: "{}", home: home)
    let perms = try FileManager.default.attributesOfItem(atPath: MyNotchPaths(home: home).inbox.path)[.posixPermissions] as? Int
    #expect(perms == 0o700)
}

@Test func noTempFilesLeftBehind() throws {
    let home = try makeTempHome()
    defer { try? FileManager.default.removeItem(at: home) }

    _ = try runReporter(args: ["codex", "Stop"], stdin: "{}", home: home)
    let names = try FileManager.default.contentsOfDirectory(atPath: MyNotchPaths(home: home).inbox.path)
    #expect(names.allSatisfy { !$0.hasPrefix(".tmp-") })
}
