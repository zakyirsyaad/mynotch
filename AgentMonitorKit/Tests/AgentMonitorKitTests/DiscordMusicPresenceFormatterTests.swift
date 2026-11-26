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
    artworkURL: String? = "https://is1-ssl.mzstatic.com/image/512x512bb.jpg",
    trackURL: String? = "https://music.apple.com/us/album/midnight-city/123"
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
        artworkURL: artworkURL,
        trackURL: trackURL
    )
}

@Test func resolvesBuiltInPlayersAndCustomOverride() throws {
    let appleMusic = try #require(DiscordMediaPlayerRegistry.resolve(bundleIdentifier: "com.apple.Music"))
    #expect(appleMusic.name == "Apple Music")
    #expect(appleMusic.applicationID == "1247654840780460125")

    let spotify = try #require(DiscordMediaPlayerRegistry.resolve(bundleIdentifier: "com.spotify.client"))
    #expect(spotify.name == "Spotify")
    #expect(spotify.applicationID == "1247651846936596540")

    let ytMusic = try #require(DiscordMediaPlayerRegistry.resolve(bundleIdentifier: "com.github.th-ch.youtube-music"))
    #expect(ytMusic.name == "YouTube Music")

    // Unknown bundle without custom ID returns nil
    #expect(DiscordMediaPlayerRegistry.resolve(bundleIdentifier: "com.unknown.browser") == nil)

    // Custom ID overrides applicationID for known or unknown players
    let customKnown = try #require(
        DiscordMediaPlayerRegistry.resolve(bundleIdentifier: "com.apple.Music", customApplicationID: "999999")
    )
    #expect(customKnown.name == "Apple Music")
    #expect(customKnown.applicationID == "999999")

    let customUnknown = try #require(
        DiscordMediaPlayerRegistry.resolve(bundleIdentifier: "com.unknown.player", customApplicationID: "888888")
    )
    #expect(customUnknown.applicationID == "888888")
}

@Test func buildsListeningActivityWithLiveTimestampsStatusDisplayAndButton() throws {
    let now = Date(timeIntervalSince1970: 1_010) // +10s since timestampDate -> elapsed = 70s
    let activity = try #require(
        DiscordMusicPresenceFormatter.activity(
            from: makeTrack(),
            enabled: true,
            options: DiscordMusicPresenceOptions(statusDisplayType: .artist),
            now: now
        )
    )
    #expect(activity.type == 2)
    #expect(activity.details == "Midnight City")
    #expect(activity.state == "M83")
    #expect(activity.largeText == "Hurry Up, We're Dreaming")
    #expect(activity.largeImage == "https://is1-ssl.mzstatic.com/image/512x512bb.jpg")
    #expect(activity.startTimestamp == 940) // 1010 - 70
    #expect(activity.endTimestamp == 1180) // 940 + 240
    #expect(activity.statusDisplayType == .artist)
    #expect(activity.buttons.count == 1)

    let json = activity.toJSONValue()
    #expect(json["status_display_type"] == .number(1))
    #expect(json["timestamps"]?["start"] == .number(940))
    #expect(json["timestamps"]?["end"] == .number(1180))
    #expect(json["assets"]?["large_image"] == .string("https://is1-ssl.mzstatic.com/image/512x512bb.jpg"))
    #expect(json["buttons"]?.arrayValue?.count == 1)
}

@Test func supportsSpotifyAndOtherBuiltInPlayers() throws {
    let activity = try #require(
        DiscordMusicPresenceFormatter.activity(
            from: makeTrack(bundleIdentifier: "com.spotify.client"),
            enabled: true,
            now: Date(timeIntervalSince1970: 1_000)
        )
    )
    #expect(activity.type == 2)
    #expect(activity.details == "Midnight City")
}

@Test func returnsNilWhenDisabledPausedUnknownPlayerOrEmpty() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(DiscordMusicPresenceFormatter.activity(from: makeTrack(), enabled: false, now: now) == nil)
    #expect(DiscordMusicPresenceFormatter.activity(from: nil, enabled: true, now: now) == nil)
    #expect(DiscordMusicPresenceFormatter.activity(from: makeTrack(isPlaying: false), enabled: true, now: now) == nil)
    #expect(DiscordMusicPresenceFormatter.activity(from: makeTrack(bundleIdentifier: "com.unknown.app"), enabled: true, now: now) == nil)
    #expect(DiscordMusicPresenceFormatter.activity(from: makeTrack(title: "   "), enabled: true, now: now) == nil)
}

@Test func respectsOptionsAndZeroDuration() throws {
    let activity = try #require(
        DiscordMusicPresenceFormatter.activity(
            from: makeTrack(album: "Album", duration: 0, artworkURL: nil),
            enabled: true,
            options: DiscordMusicPresenceOptions(
                statusDisplayType: .trackTitle,
                showAlbumName: false,
                showPlaybackDuration: false,
                showSongLinkButton: false
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )
    )
    #expect(activity.startTimestamp == nil)
    #expect(activity.endTimestamp == nil)
    #expect(activity.largeText == nil)
    #expect(activity.buttons.isEmpty)
    #expect(activity.toJSONValue()["timestamps"] == nil)
    #expect(activity.toJSONValue()["assets"] == nil)
    #expect(activity.toJSONValue()["buttons"] == nil)
    #expect(activity.toJSONValue()["status_display_type"] == .number(2))
}

@Test func clampsSingleCharAndOverlongDiscordFields() throws {
    let longTitle = String(repeating: "A", count: 150)
    let activity = try #require(
        DiscordMusicPresenceFormatter.activity(
            from: makeTrack(title: longTitle, artist: "X", album: "M"),
            enabled: true,
            now: Date(timeIntervalSince1970: 1_000)
        )
    )
    #expect(activity.details.count == 128)
    #expect(activity.state == "X ")
    #expect(activity.largeText == "M ")
}
