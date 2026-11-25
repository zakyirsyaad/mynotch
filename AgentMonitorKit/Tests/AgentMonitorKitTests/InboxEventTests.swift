import Foundation
import Testing
@testable import AgentMonitorKit

@Test func decodesEnvelope() throws {
    let json = #"{"v":1,"source":"claude-code","event":"Stop","pid":42,"ts":1764062000,"payload":{"session_id":"abc"}}"#
    let event = try InboxEvent.decode(Data(json.utf8))
    #expect(event.source == "claude-code")
    #expect(event.event == "Stop")
    #expect(event.pid == 42)
    #expect(event.timestamp == Date(timeIntervalSince1970: 1764062000))
    #expect(event.payload["session_id"]?.stringValue == "abc")
}

@Test func nullPayloadAccepted() throws {
    let json = #"{"v":1,"source":"codex","event":"Stop","pid":1,"ts":0,"payload":null}"#
    #expect(try InboxEvent.decode(Data(json.utf8)).payload == .null)
}

@Test func rejectsUnknownVersion() {
    let json = #"{"v":2,"source":"x","event":"Stop","pid":1,"ts":0,"payload":null}"#
    #expect(throws: InboxDecodeError.unsupportedVersion(2)) {
        try InboxEvent.decode(Data(json.utf8))
    }
}

@Test func rejectsGarbage() {
    #expect(throws: InboxDecodeError.malformed) {
        try InboxEvent.decode(Data("not json".utf8))
    }
}
