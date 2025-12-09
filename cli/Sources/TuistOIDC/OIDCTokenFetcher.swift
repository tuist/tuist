import Foundation
import Mockable

@Mockable
protocol OIDCTokenFetching {
    func fetchToken(requestURL: String, requestToken: String, audience: String) async throws -> String
}

enum OIDCTokenFetcherError: LocalizedError, Equatable {
    case invalidTokenRequestURL
    case tokenRequestFailed

    var errorDescription: String? {
        switch self {
        case .invalidTokenRequestURL:
            "Invalid OIDC token request URL."
        case .tokenRequestFailed:
            "Failed to fetch OIDC token."
        }
    }
}

struct OIDCTokenFetcher: OIDCTokenFetching {
    func fetchToken(requestURL: String, requestToken: String, audience: String) async throws -> String {
        guard var urlComponents = URLComponents(string: requestURL) else {
            throw OIDCTokenFetcherError.invalidTokenRequestURL
        }

        var queryItems = urlComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "audience", value: audience))
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw OIDCTokenFetcherError.invalidTokenRequestURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw OIDCTokenFetcherError.tokenRequestFailed
        }

        struct OIDCTokenResponse: Decodable {
            let value: String
        }

        let tokenResponse = try JSONDecoder().decode(OIDCTokenResponse.self, from: data)
        return tokenResponse.value
    }
}
