import Foundation
import Testing
@testable import AgentMonitorKit

private func makeTrack(
    title: String = "Midnight City",
    artist: String = "M83",
    album: String = "Hurry Up, We're Dreaming",
    duration: TimeInterval = 240,
    elapsed: TimeInterval = 60,
    timestampDate: Date = Date(timeIntervalSince1970: 1_000),
    playbackRate: Double = 1.0,
    isPlaying: Bool = true,
    bundleIdentifier: String? = "com.apple.Music",
    artworkURL: String? = "https://is1-ssl.mzstatic.com/image/512x512bb.jpg"
) -> DiscordMusicTrack {
    DiscordMusicTrack(
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        elapsed: elapsed,
        timestampDate: timestampDate,
        playbackRate: playbackRate,
        isPlaying: isPlaying,
        bundleIdentifier: bundleIdentifier,
        artworkURL: artworkURL
    )
}

@Test func buildsListeningActivityWithLiveTimestamps() throws {
    let now = Date(timeIntervalSince1970: 1_010) // +10s since timestampDate -> elapsed = 70s
    let activity = try #require(
        DiscordMusicPresenceFormatter.activity(from: makeTrack(), enabled: true, now: now)
    )
    #expect(activity.type == 2)
    #expect(activity.details == "Midnight City")
    #expect(activity.state == "M83")
    #expect(activity.largeText == "Hurry Up, We're Dreaming")
    #expect(activity.largeImage == "https://is1-ssl.mzstatic.com/image/512x512bb.jpg")
    #expect(activity.startTimestamp == 940) // 1010 - 70
    #expect(activity.endTimestamp == 1180) // 940 + 240

    let json = activity.toJSONValue()
    #expect(json["timestamps"]?["start"] == .number(940))
    #expect(json["timestamps"]?["end"] == .number(1180))
    #expect(json["assets"]?["large_image"] == .string("https://is1-ssl.mzstatic.com/image/512x512bb.jpg"))
}

@Test func returnsNilWhenDisabledPausedNonAppleMusicOrEmpty() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(DiscordMusicPresenceFormatter.activity(from: makeTrack(), enabled: false, now: now) == nil)
    #expect(DiscordMusicPresenceFormatter.activity(from: nil, enabled: true, now: now) == nil)
    #expect(DiscordMusicPresenceFormatter.activity(from: makeTrack(isPlaying: false), enabled: true, now: now) == nil)
    #expect(DiscordMusicPresenceFormatter.activity(from: makeTrack(bundleIdentifier: "com.spotify.client"), enabled: true, now: now) == nil)
    #expect(DiscordMusicPresenceFormatter.activity(from: makeTrack(title: "   "), enabled: true, now: now) == nil)
}

@Test func zeroDurationOmitsTimestampsAndEmptyAlbumOmitsAssets() throws {
    let activity = try #require(
        DiscordMusicPresenceFormatter.activity(
            from: makeTrack(album: "", duration: 0, artworkURL: nil),
            enabled: true,
            now: Date(timeIntervalSince1970: 1_000)
        )
    )
    #expect(activity.startTimestamp == nil)
    #expect(activity.endTimestamp == nil)
    #expect(activity.toJSONValue()["timestamps"] == nil)
    #expect(activity.toJSONValue()["assets"] == nil)
}
