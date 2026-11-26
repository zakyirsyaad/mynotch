import Foundation

struct DiscordOAuthTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
}

enum DiscordOAuthError: LocalizedError {
    case missingClientSecret
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingClientSecret:
            return "Client Secret belum diisi."
        case .invalidResponse:
            return "Respons OAuth Discord tidak valid."
        case .httpError(let code):
            return "Otorisasi Discord gagal (HTTP \(code))."
        }
    }
}

enum DiscordOAuthService {
    private static let tokenEndpoint = URL(string: "https://discord.com/api/oauth2/token")!
    private static let redirectURI = "http://127.0.0.1"

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
    }

    static func exchangeCode(
        _ code: String,
        clientID: String,
        clientSecret: String
    ) async throws -> DiscordOAuthTokens {
        try await requestToken(params: [
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI
        ])
    }

    static func refreshAccessToken(
        _ refreshToken: String,
        clientID: String,
        clientSecret: String
    ) async throws -> DiscordOAuthTokens {
        try await requestToken(params: [
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
    }

    private static func requestToken(params: [String: String]) async throws -> DiscordOAuthTokens {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DiscordOAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DiscordOAuthError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return DiscordOAuthTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token
        )
    }
}
