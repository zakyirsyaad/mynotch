import Foundation

public struct DiscordMediaPlayer: Sendable, Equatable {
    public let id: String
    public let name: String
    public let applicationID: String
    public let bundleIdentifiers: [String]

    public init(
        id: String,
        name: String,
        applicationID: String,
        bundleIdentifiers: [String]
    ) {
        self.id = id
        self.name = name
        self.applicationID = applicationID
        self.bundleIdentifiers = bundleIdentifiers
    }
}

public enum DiscordMediaPlayerRegistry {
    public static let builtInPlayers: [DiscordMediaPlayer] = [
        DiscordMediaPlayer(
            id: "apple-music",
            name: "Apple Music",
            applicationID: "1247654840780460125",
            bundleIdentifiers: ["com.apple.Music"]
        ),
        DiscordMediaPlayer(
            id: "spotify",
            name: "Spotify",
            applicationID: "1247651846936596540",
            bundleIdentifiers: ["com.spotify.client"]
        ),
        DiscordMediaPlayer(
            id: "youtube-music",
            name: "YouTube Music",
            applicationID: "1247847788302172273",
            bundleIdentifiers: [
                "com.github.th-ch.youtube-music",
                "com.webcatalog.juli.youtube-music"
            ]
        ),
        DiscordMediaPlayer(
            id: "tidal",
            name: "TIDAL",
            applicationID: "1246943204411179120",
            bundleIdentifiers: ["com.tidal.desktop"]
        ),
        DiscordMediaPlayer(
            id: "deezer",
            name: "Deezer",
            applicationID: "1247654082215284847",
            bundleIdentifiers: ["com.deezer.deezer-desktop"]
        ),
        DiscordMediaPlayer(
            id: "cider",
            name: "Cider",
            applicationID: "1302023626018787379",
            bundleIdentifiers: ["sh.cider.electron", "sh.cider.genten.mac"]
        ),
        DiscordMediaPlayer(
            id: "apple-podcasts",
            name: "Apple Podcasts",
            applicationID: "1308949234829234228",
            bundleIdentifiers: ["com.apple.podcasts"]
        ),
        DiscordMediaPlayer(
            id: "amazon-music",
            name: "Amazon Music",
            applicationID: "1247654006587789363",
            bundleIdentifiers: ["com.amazon.music"]
        ),
        DiscordMediaPlayer(
            id: "vlc",
            name: "VLC",
            applicationID: "1285586777616420885",
            bundleIdentifiers: ["org.videolan.vlc"]
        ),
        DiscordMediaPlayer(
            id: "iina",
            name: "IINA",
            applicationID: "1449324750357663785",
            bundleIdentifiers: ["com.colliderli.iina"]
        ),
        DiscordMediaPlayer(
            id: "vox",
            name: "VOX",
            applicationID: "1426851601171222679",
            bundleIdentifiers: ["com.coppertino.Vox"]
        ),
        DiscordMediaPlayer(
            id: "swinsian",
            name: "Swinsian",
            applicationID: "1399034733018615971",
            bundleIdentifiers: ["com.swinsian.Swinsian"]
        )
    ]

    public static func resolve(
        bundleIdentifier: String?,
        customApplicationID: String? = nil
    ) -> DiscordMediaPlayer? {
        let trimmedCustom = customApplicationID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBundle = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let matched = normalizedBundle.flatMap { bundle in
            builtInPlayers.first { player in
                player.bundleIdentifiers.contains { $0.lowercased() == bundle }
            }
        }

        if let trimmedCustom, !trimmedCustom.isEmpty {
            if let matched {
                return DiscordMediaPlayer(
                    id: matched.id,
                    name: matched.name,
                    applicationID: trimmedCustom,
                    bundleIdentifiers: matched.bundleIdentifiers
                )
            }
            guard let normalizedBundle, !normalizedBundle.isEmpty else {
                return nil
            }
            return DiscordMediaPlayer(
                id: "custom",
                name: "Music",
                applicationID: trimmedCustom,
                bundleIdentifiers: [normalizedBundle]
            )
        }

        return matched
    }
}
