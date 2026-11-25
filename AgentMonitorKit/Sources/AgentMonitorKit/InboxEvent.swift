import Foundation

public enum InboxDecodeError: Error, Equatable, Sendable {
    case malformed
    case unsupportedVersion(Int)
}

public struct InboxEvent: Sendable, Equatable {
    public let version: Int
    public let source: String
    public let event: String
    public let pid: Int32
    public let timestamp: Date
    public let payload: JSONValue

    public init(
        version: Int,
        source: String,
        event: String,
        pid: Int32,
        timestamp: Date,
        payload: JSONValue
    ) {
        self.version = version
        self.source = source
        self.event = event
        self.pid = pid
        self.timestamp = timestamp
        self.payload = payload
    }

    private struct Envelope: Decodable {
        let v: Int
        let source: String
        let event: String
        let pid: Int32
        let ts: Double
        let payload: JSONValue
    }

    private struct VersionProbe: Decodable {
        let v: Int
    }

    public static func decode(_ data: Data) throws(InboxDecodeError) -> InboxEvent {
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            guard envelope.v == 1 else {
                throw InboxDecodeError.unsupportedVersion(envelope.v)
            }
            return InboxEvent(
                version: envelope.v,
                source: envelope.source,
                event: envelope.event,
                pid: envelope.pid,
                timestamp: Date(timeIntervalSince1970: envelope.ts),
                payload: envelope.payload
            )
        } catch let error as InboxDecodeError {
            throw error
        } catch {
            if let probe = try? decoder.decode(VersionProbe.self, from: data), probe.v != 1 {
                throw InboxDecodeError.unsupportedVersion(probe.v)
            }
            throw InboxDecodeError.malformed
        }
    }
}
