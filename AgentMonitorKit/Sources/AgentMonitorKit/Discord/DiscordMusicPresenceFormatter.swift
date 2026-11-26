import Foundation

public struct DiscordMusicTrack: Sendable, Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let elapsed: TimeInterval
    public let timestampDate: Date
    public let playbackRate: Double
    public let isPlaying: Bool
    public let bundleIdentifier: String?
    public let artworkURL: String?

    public init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        timestampDate: Date,
        playbackRate: Double = 1.0,
        isPlaying: Bool,
        bundleIdentifier: String?,
        artworkURL: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestampDate = timestampDate
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.bundleIdentifier = bundleIdentifier
        self.artworkURL = artworkURL
    }
}

public struct DiscordPresenceActivity: Sendable, Equatable {
    public let type: Int
    public let details: String
    public let state: String
    public let startTimestamp: Int?
    public let endTimestamp: Int?
    public let largeImage: String?
    public let largeText: String?

    public init(
        type: Int,
        details: String,
        state: String,
        startTimestamp: Int? = nil,
        endTimestamp: Int? = nil,
        largeImage: String? = nil,
        largeText: String? = nil
    ) {
        self.type = type
        self.details = details
        self.state = state
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.largeImage = largeImage
        self.largeText = largeText
    }

    public func toJSONValue() -> JSONValue {
        var obj: [String: JSONValue] = [
            "type": .number(Double(type)),
            "details": .string(details)
        ]

        if !state.isEmpty {
            obj["state"] = .string(state)
        }

        var timestamps: [String: JSONValue] = [:]
        if let startTimestamp {
            timestamps["start"] = .number(Double(startTimestamp))
        }
        if let endTimestamp {
            timestamps["end"] = .number(Double(endTimestamp))
        }
        if !timestamps.isEmpty {
            obj["timestamps"] = .object(timestamps)
        }

        var assets: [String: JSONValue] = [:]
        if let largeImage, !largeImage.isEmpty {
            assets["large_image"] = .string(largeImage)
        }
        if let largeText, !largeText.isEmpty {
            assets["large_text"] = .string(largeText)
        }
        if !assets.isEmpty {
            obj["assets"] = .object(assets)
        }

        return .object(obj)
    }
}

public enum DiscordMusicPresenceFormatter {
    public static let appleMusicBundleID = "com.apple.Music"

    public static func activity(
        from track: DiscordMusicTrack?,
        enabled: Bool,
        now: Date = Date()
    ) -> DiscordPresenceActivity? {
        guard enabled,
              let track,
              track.isPlaying,
              track.bundleIdentifier == appleMusicBundleID
        else {
            return nil
        }

        let title = clampDiscordText(track.title)
        guard !title.isEmpty else { return nil }

        let artist = clampDiscordText(track.artist)
        let album = clampDiscordText(track.album)

        let rate = track.playbackRate > 0 ? track.playbackRate : 1.0
        let delta = max(0, now.timeIntervalSince(track.timestampDate)) * rate
        let currentElapsed = max(0, track.elapsed + delta)

        let startTimestamp: Int?
        let endTimestamp: Int?
        if track.duration > 0 {
            let clampedElapsed = min(currentElapsed, track.duration)
            let start = now.timeIntervalSince1970 - clampedElapsed
            let end = start + track.duration
            startTimestamp = Int(start.rounded())
            endTimestamp = Int(end.rounded())
        } else {
            startTimestamp = nil
            endTimestamp = nil
        }

        return DiscordPresenceActivity(
            type: 2,
            details: title,
            state: artist,
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            largeImage: track.artworkURL,
            largeText: album.isEmpty ? nil : album
        )
    }

    private static func clampDiscordText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count == 1 {
            return trimmed + " "
        }
        if trimmed.count > 128 {
            return String(trimmed.prefix(128))
        }
        return trimmed
    }
}
