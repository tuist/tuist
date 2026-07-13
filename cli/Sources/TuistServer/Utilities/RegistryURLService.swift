import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Mockable

/// The Swift package registry configuration a server advertises at
/// `/.well-known/registry.json`.
public struct RegistryConfiguration: Equatable, Sendable {
    /// The base URL clients configure SwiftPM against (e.g.
    /// `https://registry.tuist.dev/swift`).
    public let url: URL
    /// The registry login path relative to `url`'s host (e.g. `/swift/login`).
    public let loginAPIPath: String

    public init(url: URL, loginAPIPath: String) {
        self.url = url
        self.loginAPIPath = loginAPIPath
    }
}

@Mockable
public protocol RegistryURLServicing {
    /// Resolves the registry configuration a server advertises at its
    /// `/.well-known/registry.json` discovery endpoint. Returns `nil`
    /// when the server exposes no registry (self-hosted deployments), letting
    /// callers report that instead of writing a broken URL.
    func registryConfiguration(serverURL: URL) async throws -> RegistryConfiguration?
}

enum RegistryURLServiceError: LocalizedError, Equatable {
    case invalidResponse(URL)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(url):
            return "The registry discovery endpoint at \(url.absoluteString) returned an unexpected response."
        case let .invalidURL(value):
            return "The server advertised an invalid registry URL: \(value)."
        }
    }
}

public struct RegistryURLService: RegistryURLServicing {
    private let urlSession: URLSession

    public init() {
        self.init(urlSession: URLSession.shared)
    }

    init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    public func registryConfiguration(serverURL: URL) async throws -> RegistryConfiguration? {
        let discoveryURL = serverURL.appending(path: ".well-known/registry.json")

        var request = URLRequest(url: discoveryURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RegistryURLServiceError.invalidResponse(discoveryURL)
        }

        // The server 404s the endpoint when the deployment exposes no
        // registry (self-hosted). Treat that as "no registry", not an error.
        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw RegistryURLServiceError.invalidResponse(discoveryURL)
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)

        // The discovery document is keyed by ecosystem so future ones (e.g.
        // Gradle) are additive. A 200 without a `swift` entry means the
        // deployment has a registry but not for Swift, which is the same
        // "no registry to configure" outcome as a 404 for this command.
        guard let swift = payload.ecosystems["swift"] else {
            return nil
        }

        guard let url = URL(string: swift.url) else {
            throw RegistryURLServiceError.invalidURL(swift.url)
        }

        return RegistryConfiguration(url: url, loginAPIPath: swift.loginAPIPath)
    }

    private struct Payload: Decodable {
        let ecosystems: [String: Ecosystem]

        struct Ecosystem: Decodable {
            let url: String
            let loginAPIPath: String
        }
    }
}
