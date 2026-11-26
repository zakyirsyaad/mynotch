import Foundation

public enum DiscordIPCOpcode: UInt32, Sendable, Equatable {
    case handshake = 0
    case frame = 1
    case close = 2
    case ping = 3
    case pong = 4
}

public struct DiscordIPCFrame: Sendable, Equatable {
    public let opcode: DiscordIPCOpcode
    public let payload: Data

    public init(opcode: DiscordIPCOpcode, payload: Data) {
        self.opcode = opcode
        self.payload = payload
    }
}

public enum DiscordIPCError: Error, Equatable, Sendable {
    case unknownOpcode(UInt32)
    case payloadTooLarge(Int)
    case malformedJSON
}

public enum DiscordIPCFramer {
    public static let maxFramePayloadBytes = 1_048_576

    public static func encode(opcode: DiscordIPCOpcode, payload: Data) -> Data {
        var result = Data(capacity: 8 + payload.count)
        var rawOpcode = opcode.rawValue.littleEndian
        var rawLength = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &rawOpcode) { result.append(contentsOf: $0) }
        withUnsafeBytes(of: &rawLength) { result.append(contentsOf: $0) }
        result.append(payload)
        return result
    }

    public static func encodeJSON(_ value: JSONValue, opcode: DiscordIPCOpcode = .frame) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let jsonData = try encoder.encode(value)
        return encode(opcode: opcode, payload: jsonData)
    }

    public static func decodeNextFrame(from buffer: inout Data) throws -> DiscordIPCFrame? {
        guard buffer.count >= 8 else { return nil }

        let base = buffer.startIndex
        let rawOpcode = readUInt32LE(buffer, offset: base)
        let rawLength = readUInt32LE(buffer, offset: base + 4)

        guard let opcode = DiscordIPCOpcode(rawValue: rawOpcode) else {
            throw DiscordIPCError.unknownOpcode(rawOpcode)
        }

        let length = Int(rawLength)
        guard length <= maxFramePayloadBytes else {
            throw DiscordIPCError.payloadTooLarge(length)
        }

        let totalSize = 8 + length
        guard buffer.count >= totalSize else {
            return nil
        }

        let payloadStart = base + 8
        let payloadEnd = payloadStart + length
        let payload = Data(buffer[payloadStart..<payloadEnd])
        buffer.removeFirst(totalSize)
        return DiscordIPCFrame(opcode: opcode, payload: payload)
    }

    public static func handshakePayload(clientID: String) -> JSONValue {
        .object([
            "v": .number(1),
            "client_id": .string(clientID)
        ])
    }

    public static func setActivityPayload(
        pid: Int32,
        nonce: String,
        activity: DiscordPresenceActivity?
    ) -> JSONValue {
        .object([
            "cmd": .string("SET_ACTIVITY"),
            "args": .object([
                "pid": .number(Double(pid)),
                "activity": activity?.toJSONValue() ?? .null
            ]),
            "nonce": .string(nonce)
        ])
    }

    public static func authorizePayload(
        clientID: String,
        scopes: [String],
        nonce: String
    ) -> JSONValue {
        .object([
            "cmd": .string("AUTHORIZE"),
            "args": .object([
                "client_id": .string(clientID),
                "scopes": .array(scopes.map(JSONValue.string))
            ]),
            "nonce": .string(nonce)
        ])
    }

    public static func authenticatePayload(accessToken: String, nonce: String) -> JSONValue {
        .object([
            "cmd": .string("AUTHENTICATE"),
            "args": .object([
                "access_token": .string(accessToken)
            ]),
            "nonce": .string(nonce)
        ])
    }

    public static func subscribePayload(
        event: String,
        args: [String: JSONValue]? = nil,
        nonce: String
    ) -> JSONValue {
        var obj: [String: JSONValue] = [
            "cmd": .string("SUBSCRIBE"),
            "evt": .string(event),
            "nonce": .string(nonce)
        ]
        if let args, !args.isEmpty {
            obj["args"] = .object(args)
        }
        return .object(obj)
    }

    public static func unsubscribePayload(
        event: String,
        args: [String: JSONValue]? = nil,
        nonce: String
    ) -> JSONValue {
        var obj: [String: JSONValue] = [
            "cmd": .string("UNSUBSCRIBE"),
            "evt": .string(event),
            "nonce": .string(nonce)
        ]
        if let args, !args.isEmpty {
            obj["args"] = .object(args)
        }
        return .object(obj)
    }

    public static func getSelectedVoiceChannelPayload(nonce: String) -> JSONValue {
        .object([
            "cmd": .string("GET_SELECTED_VOICE_CHANNEL"),
            "nonce": .string(nonce)
        ])
    }

    public static func getVoiceSettingsPayload(nonce: String) -> JSONValue {
        .object([
            "cmd": .string("GET_VOICE_SETTINGS"),
            "nonce": .string(nonce)
        ])
    }

    public static func setVoiceSettingsPayload(
        mute: Bool?,
        deaf: Bool?,
        nonce: String
    ) -> JSONValue {
        var args: [String: JSONValue] = [:]
        if let mute {
            args["mute"] = .bool(mute)
        }
        if let deaf {
            args["deaf"] = .bool(deaf)
        }
        return .object([
            "cmd": .string("SET_VOICE_SETTINGS"),
            "args": .object(args),
            "nonce": .string(nonce)
        ])
    }

    public static func selectVoiceChannelPayload(channelID: String?, nonce: String) -> JSONValue {
        .object([
            "cmd": .string("SELECT_VOICE_CHANNEL"),
            "args": .object([
                "channel_id": channelID.map(JSONValue.string) ?? .null
            ]),
            "nonce": .string(nonce)
        ])
    }

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
