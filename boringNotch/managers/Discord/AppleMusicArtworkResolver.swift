import Foundation

struct AppleMusicMetadata: Sendable, Equatable {
    let artworkURL: String?
    let trackURL: String?
}

actor AppleMusicArtworkResolver {
    static let shared = AppleMusicArtworkResolver()

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let artworkUrl100: String?
            let trackViewUrl: String?
        }
        let results: [Item]
    }

    private var cache: [String: AppleMusicMetadata] = [:]

    func metadata(artist: String, title: String) async -> AppleMusicMetadata {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return AppleMusicMetadata(artworkURL: nil, trackURL: nil)
        }

        let cacheKey = "\(cleanArtist.lowercased())|\(cleanTitle.lowercased())"
        if let cached = cache[cacheKey] {
            return cached
        }

        let term = cleanArtist.isEmpty ? cleanTitle : "\(cleanArtist) \(cleanTitle)"
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            return AppleMusicMetadata(artworkURL: nil, trackURL: nil)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return AppleMusicMetadata(artworkURL: nil, trackURL: nil)
            }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let first = decoded.results.first
            let upgradedArtwork = first?.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "512x512bb")
            let result = AppleMusicMetadata(
                artworkURL: upgradedArtwork,
                trackURL: first?.trackViewUrl
            )
            if cache.count >= 200 {
                cache.removeAll()
            }
            cache[cacheKey] = result
            return result
        } catch {
            return AppleMusicMetadata(artworkURL: nil, trackURL: nil)
        }
    }
}
