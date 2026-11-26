import Foundation

public struct DiscordMediaPlayer: Sendable, Equatable {
    public let id: String
    public let name: String
    public let applicationID: String
    public let iconURL: String?
    public let bundleIdentifiers: [String]

    public init(
        id: String,
        name: String,
        applicationID: String,
        iconURL: String? = nil,
        bundleIdentifiers: [String]
    ) {
        self.id = id
        self.name = name
        self.applicationID = applicationID
        self.iconURL = iconURL
        self.bundleIdentifiers = bundleIdentifiers
    }
}

public enum DiscordMediaPlayerRegistry {
    private static func cdnIcon(appID: String, hash: String) -> String {
        "https://cdn.discordapp.com/app-icons/\(appID)/\(hash).png?size=256"
    }

    public static let builtInPlayers: [DiscordMediaPlayer] = [
        DiscordMediaPlayer(
            id: "apple-music",
            name: "Apple Music",
            applicationID: "1247654840780460125",
            iconURL: cdnIcon(appID: "1247654840780460125", hash: "393590f736eaf7d08120700c39b259d7"),
            bundleIdentifiers: ["com.apple.Music"]
        ),
        DiscordMediaPlayer(
            id: "spotify",
            name: "Spotify",
            applicationID: "1247651846936596540",
            iconURL: cdnIcon(appID: "1247651846936596540", hash: "52b9f067071f9efb4b843037612763dc"),
            bundleIdentifiers: ["com.spotify.client"]
        ),
        DiscordMediaPlayer(
            id: "youtube-music",
            name: "YouTube Music",
            applicationID: "1247847788302172273",
            iconURL: cdnIcon(appID: "1247847788302172273", hash: "83ba65d4b4edc2ead78cecbb85f172d4"),
            bundleIdentifiers: [
                "com.github.th-ch.youtube-music",
                "com.webcatalog.juli.youtube-music"
            ]
        ),
        DiscordMediaPlayer(
            id: "tidal",
            name: "TIDAL",
            applicationID: "1246943204411179120",
            iconURL: cdnIcon(appID: "1246943204411179120", hash: "05a6dfc61b7ca6a34344ef431bc02c87"),
            bundleIdentifiers: ["com.tidal.desktop"]
        ),
        DiscordMediaPlayer(
            id: "deezer",
            name: "Deezer",
            applicationID: "1247654082215284847",
            iconURL: cdnIcon(appID: "1247654082215284847", hash: "5d30765b2cee9491b0eb5da21b2ff626"),
            bundleIdentifiers: ["com.deezer.deezer-desktop"]
        ),
        DiscordMediaPlayer(
            id: "cider",
            name: "Cider",
            applicationID: "1302023626018787379",
            iconURL: cdnIcon(appID: "1302023626018787379", hash: "5f05738007347766d6d761d5e4aa99a2"),
            bundleIdentifiers: ["sh.cider.electron", "sh.cider.genten.mac"]
        ),
        DiscordMediaPlayer(
            id: "apple-podcasts",
            name: "Apple Podcasts",
            applicationID: "1308949234829234228",
            iconURL: cdnIcon(appID: "1308949234829234228", hash: "6d70a5ab70ee6430d7c591331b434c57"),
            bundleIdentifiers: ["com.apple.podcasts"]
        ),
        DiscordMediaPlayer(
            id: "amazon-music",
            name: "Amazon Music",
            applicationID: "1247654006587789363",
            iconURL: cdnIcon(appID: "1247654006587789363", hash: "688da2b223a93527bc7f82ee422067a1"),
            bundleIdentifiers: ["com.amazon.music"]
        ),
        DiscordMediaPlayer(
            id: "vlc",
            name: "VLC",
            applicationID: "1285586777616420885",
            iconURL: cdnIcon(appID: "1285586777616420885", hash: "403c1c02d298f365a809cd0eccf7b467"),
            bundleIdentifiers: ["org.videolan.vlc"]
        ),
        DiscordMediaPlayer(
            id: "iina",
            name: "IINA",
            applicationID: "1449324750357663785",
            iconURL: cdnIcon(appID: "1449324750357663785", hash: "3d5d4b6ac85658f9f5743ced6ab32a0a"),
            bundleIdentifiers: ["com.colliderli.iina"]
        ),
        DiscordMediaPlayer(
            id: "vox",
            name: "VOX",
            applicationID: "1426851601171222679",
            iconURL: cdnIcon(appID: "1426851601171222679", hash: "2ce843b13a5a227a8dffc8b0a8b79655"),
            bundleIdentifiers: ["com.coppertino.Vox"]
        ),
        DiscordMediaPlayer(
            id: "swinsian",
            name: "Swinsian",
            applicationID: "1399034733018615971",
            iconURL: cdnIcon(appID: "1399034733018615971", hash: "89867219ec34ead0f093ebebd75257f2"),
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
                    iconURL: matched.iconURL,
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
                iconURL: nil,
                bundleIdentifiers: [normalizedBundle]
            )
        }

        return matched
    }
}
