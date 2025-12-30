import Foundation
import Mockable

@Mockable
protocol OIDCTokenFetching {
    func fetchToken(requestURL: String, requestToken: String, audience: String) async throws -> String
}

enum OIDCTokenFetcherError: LocalizedError, Equatable {
    case invalidTokenRequestURL(String)
    case tokenRequestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case let .invalidTokenRequestURL(url):
            "Invalid OIDC token request URL: \(url)"
        case let .tokenRequestFailed(statusCode, body):
            "Failed to fetch OIDC token. Status code: \(statusCode). Response: \(body)"
        }
    }
}

struct OIDCTokenFetcher: OIDCTokenFetching {
    func fetchToken(requestURL: String, requestToken: String, audience: String) async throws -> String {
        guard var urlComponents = URLComponents(string: requestURL) else {
            throw OIDCTokenFetcherError.invalidTokenRequestURL(requestURL)
        }

        var queryItems = urlComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "audience", value: audience))
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw OIDCTokenFetcherError.invalidTokenRequestURL(requestURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OIDCTokenFetcherError.tokenRequestFailed(statusCode: statusCode, body: body)
        }

        let tokenResponse = try JSONDecoder().decode(OIDCTokenResponse.self, from: data)
        return tokenResponse.value
    }
}

struct OIDCTokenResponse: Decodable {
    let value: String
}
