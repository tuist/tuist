import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum ServerReportPublishingMode {
    @TaskLocal public static var serverAllowsNetworkPublishing: @Sendable (URL) async throws -> Bool = {
        try await discover($0)
    }

    public static func validateDestination(_ url: URL) throws {
        let host = (url.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              !host.isEmpty, url.user == nil, url.password == nil,
              !["tuist.dev", "tuist.io", "cloud.tuist.io", "cloud.tuist.dev"].contains(host),
              !host.hasSuffix(".tuist.dev"), !host.hasSuffix(".tuist.io")
        else { throw ServerReportPublishingError.selfHostedDestinationRequired }
    }

    public static func usesNetworkTrust(
        serverURL: URL,
        authenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) async throws -> Bool {
        guard (try? validateDestination(serverURL)) != nil else { return false }
        let token = try await ServerAuthenticationConfig.$current.withValue(.init(backgroundRefresh: false)) {
            try await authenticationController.authenticationToken(serverURL: serverURL)
        }
        if let token {
            guard !token.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ServerReportPublishingError.invalidCredentials }
            return false
        }
        return try await serverAllowsNetworkPublishing(serverURL)
    }

    static func discover(
        _ serverURL: URL,
        perform: @Sendable (URLRequest) async throws -> (Data, URLResponse) = performDiscovery
    ) async throws -> Bool {
        let url = serverURL.appendingPathComponent(".well-known/tuist.json")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await perform(request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { return false }
        struct Capabilities: Decodable {
            let networkTrustedReportPublishing: Bool?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(Capabilities.self, from: data))?.networkTrustedReportPublishing == true
    }

    private static func performDiscovery(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoDiscoveryRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }
}

private final class NoDiscoveryRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum ServerReportPublishingError: LocalizedError, Equatable {
    case selfHostedDestinationRequired
    case invalidCredentials

    public var errorDescription: String? {
        switch self {
        case .selfHostedDestinationRequired:
            "Credential-free publishing requires a configured self-hosted Tuist server URL."
        case .invalidCredentials:
            "Invalid Tuist credentials. Sign in again or explicitly sign out to remove them."
        }
    }
}
