import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Mockable
import TuistHTTP

@Mockable
protocol OIDCTokenFetching {
    func fetchToken(requestURL: String, requestToken: String, audience: String) async throws -> String
    func fetchAmpOrbToken(audience: String) async throws -> String
}

enum OIDCTokenFetcherError: LocalizedError, Equatable {
    case invalidTokenRequestURL(String)
    case tokenRequestFailed(statusCode: Int, body: String)
    case ampOrbTokenCommandFailed(exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case let .invalidTokenRequestURL(url):
            "Invalid OIDC token request URL: \(url)"
        case let .tokenRequestFailed(statusCode, body):
            "Failed to fetch OIDC token. Status code: \(statusCode). Response: \(body)"
        case let .ampOrbTokenCommandFailed(exitCode, output):
            "`amp orb id-token` failed with exit code \(exitCode). \(output)"
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

        let (data, response) = try await URLSession.tuistDefault.data(for: request)

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

extension OIDCTokenFetcher {
    func fetchAmpOrbToken(audience: String) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["amp", "orb", "id-token", "--audience", audience]
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            try process.run()
            let token = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let errorOutput = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw OIDCTokenFetcherError.ampOrbTokenCommandFailed(
                    exitCode: process.terminationStatus,
                    output: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return token.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}

struct OIDCTokenResponse: Decodable {
    let value: String
}
