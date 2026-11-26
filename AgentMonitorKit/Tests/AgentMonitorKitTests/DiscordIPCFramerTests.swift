import Foundation
import Testing
@testable import AgentMonitorKit

@Test func roundTripsSequentialFramesAndPartialBuffer() throws {
    let first = try DiscordIPCFramer.encodeJSON(DiscordIPCFramer.handshakePayload(clientID: "12345"), opcode: .handshake)
    let second = DiscordIPCFramer.encode(opcode: .ping, payload: Data("hi".utf8))

    var buffer = Data()
    buffer.append(first.prefix(4))
    #expect(try DiscordIPCFramer.decodeNextFrame(from: &buffer) == nil)
    #expect(buffer.count == 4)

    buffer.append(first.dropFirst(4))
    buffer.append(second)

    let decodedFirst = try #require(try DiscordIPCFramer.decodeNextFrame(from: &buffer))
    #expect(decodedFirst.opcode == .handshake)
    let decodedJSON = try JSONDecoder().decode(JSONValue.self, from: decodedFirst.payload)
    #expect(decodedJSON["v"] == .number(1))
    #expect(decodedJSON["client_id"] == .string("12345"))

    let decodedSecond = try #require(try DiscordIPCFramer.decodeNextFrame(from: &buffer))
    #expect(decodedSecond.opcode == .ping)
    #expect(String(decoding: decodedSecond.payload, as: UTF8.self) == "hi")
    #expect(buffer.isEmpty)
}

@Test func rejectsUnknownOpcodeAndOversizedFrame() {
    var badOpcode = Data([99, 0, 0, 0, 0, 0, 0, 0])
    #expect(throws: DiscordIPCError.unknownOpcode(99)) {
        try DiscordIPCFramer.decodeNextFrame(from: &badOpcode)
    }

    var tooLarge = Data([1, 0, 0, 0, 0x01, 0x00, 0x20, 0x00]) // 2 MiB
    #expect(throws: DiscordIPCError.payloadTooLarge(0x0020_0001)) {
        try DiscordIPCFramer.decodeNextFrame(from: &tooLarge)
    }
}

@Test func buildsRpcCommandPayloads() {
    let act = DiscordPresenceActivity(type: 2, details: "Song", state: "Artist", startTimestamp: 100, endTimestamp: 300)
    let setAct = DiscordIPCFramer.setActivityPayload(pid: 42, nonce: "n1", activity: act)
    #expect(setAct["cmd"] == .string("SET_ACTIVITY"))
    #expect(setAct["args"]?["pid"] == .number(42))
    #expect(setAct["args"]?["activity"]?["type"] == .number(2))

    let clearAct = DiscordIPCFramer.setActivityPayload(pid: 42, nonce: "n2", activity: nil)
    #expect(clearAct["args"]?["activity"] == .null)

    let auth = DiscordIPCFramer.authorizePayload(clientID: "cid", scopes: ["rpc", "rpc.voice.read"], nonce: "n3")
    #expect(auth["cmd"] == .string("AUTHORIZE"))
    #expect(auth["args"]?["scopes"]?.arrayValue?.count == 2)

    let authToken = DiscordIPCFramer.authenticatePayload(accessToken: "tok", nonce: "n4")
    #expect(authToken["cmd"] == .string("AUTHENTICATE"))

    let sub = DiscordIPCFramer.subscribePayload(event: "SPEAKING_START", nonce: "n5")
    #expect(sub["evt"] == .string("SPEAKING_START"))

    let getVoice = DiscordIPCFramer.getSelectedVoiceChannelPayload(nonce: "n6")
    #expect(getVoice["cmd"] == .string("GET_SELECTED_VOICE_CHANNEL"))

    let getSettings = DiscordIPCFramer.getVoiceSettingsPayload(nonce: "n7")
    #expect(getSettings["cmd"] == .string("GET_VOICE_SETTINGS"))

    let setVoice = DiscordIPCFramer.setVoiceSettingsPayload(mute: true, deaf: nil, nonce: "n8")
    #expect(setVoice["args"]?["mute"] == .bool(true))
    #expect(setVoice["args"]?["deaf"] == nil)

    let leave = DiscordIPCFramer.selectVoiceChannelPayload(channelID: nil, nonce: "n9")
    #expect(leave["args"]?["channel_id"] == .null)
}
