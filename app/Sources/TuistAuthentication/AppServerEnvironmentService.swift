import Foundation
import TuistAppStorage
import TuistServer

public struct AppServerConfiguration: Codable, Equatable, Sendable {
    public let url: URL
    public let oauthClientID: String

    public init(url: URL, oauthClientID: String) {
        self.url = url
        self.oauthClientID = oauthClientID
    }
}

public enum AppServerConfigurationKey: AppStorageKey {
    public static let defaultValue: AppServerConfiguration? = nil
    public static let key = "serverConfiguration"
}

public enum AppServerConfigurationError: LocalizedError {
    case invalidURL
    case unsupportedServer

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid HTTPS server URL without credentials, a query, or a fragment."
        case .unsupportedServer:
            return "This server doesn't support signing in from the Tuist app. Ask your administrator to update it."
        }
    }
}

public struct AppServerEnvironmentService: ServerEnvironmentServicing {
    private let appStorage: AppStoring
    private let defaultEnvironment: ServerEnvironmentServicing
    private let perform: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?

    public init(
        appStorage: AppStoring = AppStorage(),
        defaultEnvironment: ServerEnvironmentServicing = ServerEnvironmentService(),
        perform: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.appStorage = appStorage
        self.defaultEnvironment = defaultEnvironment
        self.perform = perform
    }

    public func url() -> URL {
        configuration?.url ?? defaultEnvironment.url()
    }

    public func url(configServerURL: URL) throws -> URL {
        try configuration?.url ?? defaultEnvironment.url(configServerURL: configServerURL)
    }

    public func oauthClientId() -> String {
        configuration?.oauthClientID ?? defaultEnvironment.oauthClientId()
    }

    /// The server of the signed-in session, or the server selected for the next sign-in when signed out.
    public var configuration: AppServerConfiguration? {
        if case let .loggedIn(_, server) = try? appStorage.get(AuthenticationStateKey.self) {
            return server
        }
        return try? appStorage.get(AppServerConfigurationKey.self)
    }

    public func selectServer(_ input: String?) async throws {
        guard let input else {
            try appStorage.set(AppServerConfigurationKey.self, value: nil)
            return
        }

        let url = try Self.validatedURL(input)
        let registrationEndpoint = try await registrationEndpoint(for: url)
        let clientID = try await registerClient(at: registrationEndpoint)
        try appStorage.set(
            AppServerConfigurationKey.self,
            value: AppServerConfiguration(url: url, oauthClientID: clientID)
        )
    }

    /// Reads the server's OAuth metadata and returns its dynamic client registration endpoint (RFC 8414).
    /// The endpoint must live on the selected server, since the app authorizes against that origin.
    private func registrationEndpoint(for url: URL) async throws -> URL {
        var request = URLRequest(url: url.appending(path: ".well-known/oauth-authorization-server"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let metadata = try await send(request, decoding: Metadata.self)
        guard let endpoint = metadata.registrationEndpoint.flatMap(URL.init(string:)),
              endpoint.scheme?.lowercased() == "https",
              endpoint.host?.lowercased() == url.host?.lowercased(),
              (endpoint.port ?? 443) == (url.port ?? 443)
        else {
            throw AppServerConfigurationError.unsupportedServer
        }
        return endpoint
    }

    /// Registers the app as a public, PKCE-only client (RFC 7591) so no client ID is hardcoded per server.
    private func registerClient(at endpoint: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Registration())
        let registered = try await send(request, decoding: RegisteredClient.self, expecting: 201)
        let clientID = registered.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw AppServerConfigurationError.unsupportedServer }
        return clientID
    }

    private func send<T: Decodable>(
        _ request: URLRequest,
        decoding _: T.Type,
        expecting statusCode: Int = 200
    ) async throws -> T {
        var request = request
        request.timeoutInterval = 30
        let (data, response) = if let perform {
            try await perform(request)
        } else {
            try await URLSession.shared.data(for: request)
        }
        guard let response = response as? HTTPURLResponse,
              response.statusCode == statusCode,
              let decoded = try? JSONDecoder().decode(T.self, from: data)
        else {
            throw AppServerConfigurationError.unsupportedServer
        }
        return decoded
    }

    public static func validatedURL(_ input: String) throws -> URL {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.contains(where: \.isWhitespace),
              var components = URLComponents(string: input),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1 ... 65535).contains($0) }) ?? true
        else {
            throw AppServerConfigurationError.invalidURL
        }
        components.scheme = "https"
        components.host = host.lowercased()
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw AppServerConfigurationError.invalidURL }
        return url
    }

    private struct Metadata: Decodable {
        let registrationEndpoint: String?

        enum CodingKeys: String, CodingKey {
            case registrationEndpoint = "registration_endpoint"
        }
    }

    private struct Registration: Encodable {
        let clientName = "Tuist app"
        let redirectURIs = ["tuist://oauth-callback"]
        let grantTypes = ["authorization_code", "refresh_token"]
        let responseTypes = ["code"]
        let tokenEndpointAuthMethod = "none"

        enum CodingKeys: String, CodingKey {
            case clientName = "client_name"
            case redirectURIs = "redirect_uris"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        }
    }

    private struct RegisteredClient: Decodable {
        let clientID: String

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
        }
    }
}
