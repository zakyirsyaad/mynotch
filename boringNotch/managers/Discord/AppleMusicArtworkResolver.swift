import Foundation

actor AppleMusicArtworkResolver {
    static let shared = AppleMusicArtworkResolver()

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let artworkUrl100: String?
        }
        let results: [Item]
    }

    private var cache: [String: String?] = [:]

    func artworkURL(artist: String, title: String) async -> String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

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

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let rawURL = decoded.results.first?.artworkUrl100
            let upgraded = rawURL?.replacingOccurrences(of: "100x100bb", with: "512x512bb")
            if cache.count >= 200 {
                cache.removeAll()
            }
            cache[cacheKey] = upgraded
            return upgraded
        } catch {
            return nil
        }
    }
}
