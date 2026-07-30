import Foundation
import TuistAppStorage
import TuistServer

public struct AppServerURLKey: AppStorageKey {
    public static let key = "serverURL"
    public static let defaultValue: String? = nil
}

public enum AppServerEnvironmentServiceError: LocalizedError, Equatable {
    case cannotChangeServerURL
    case emptyServerURL
    case insecureServerURL
    case invalidServerURL(String)
    case serverURLMustBeRoot
    case unsupportedServerURLScheme(String)

    public var errorDescription: String? {
        switch self {
        case .cannotChangeServerURL:
            return "The server address cannot be changed from this context."
        case .emptyServerURL:
            return "Enter a server address."
        case .insecureServerURL:
            return "Use https, or http for a local server."
        case let .invalidServerURL(value):
            return "\(value) is not a valid server address."
        case .serverURLMustBeRoot:
            return "Use the root server address without a path, query, or fragment."
        case let .unsupportedServerURLScheme(scheme):
            return "\(scheme) is not supported. Use http or https."
        }
    }
}

public protocol AppServerEnvironmentConfiguring: ServerEnvironmentServicing {
    func customURL() -> URL?
    func defaultURL() -> URL
    func setCustomURL(_ url: URL?) throws
}

public struct AppServerEnvironmentService: AppServerEnvironmentConfiguring {
    private let appStorage: AppStoring
    private let defaultServerEnvironmentService: ServerEnvironmentServicing

    public init(
        appStorage: AppStoring = AppStorage(),
        defaultServerEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.appStorage = appStorage
        self.defaultServerEnvironmentService = defaultServerEnvironmentService
    }

    public func url() -> URL {
        return customURL() ?? defaultURL()
    }

    public func defaultURL() -> URL {
        return defaultServerEnvironmentService.url()
    }

    public func customURL() -> URL? {
        guard let storedValue = try? appStorage.get(AppServerURLKey.self) else {
            return nil
        }
        return try? Self.normalizedURL(from: storedValue)
    }

    public func setCustomURL(_ url: URL?) throws {
        let normalizedURL = try url.map { try Self.normalizedURL(from: $0.absoluteString) }
        try appStorage.set(AppServerURLKey.self, value: normalizedURL?.absoluteString)
    }

    public func oauthClientId() -> String {
        return defaultServerEnvironmentService.oauthClientId()
    }

    public func url(configServerURL: URL) throws -> URL {
        if let customURL = customURL() {
            return customURL
        }

        return try defaultServerEnvironmentService.url(configServerURL: configServerURL)
    }

    public static func normalizedURL(from value: String) throws -> URL {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw AppServerEnvironmentServiceError.emptyServerURL
        }

        let valueWithScheme = if trimmedValue.contains("://") {
            trimmedValue
        } else {
            "https://\(trimmedValue)"
        }

        guard var components = URLComponents(string: valueWithScheme),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty
        else {
            throw AppServerEnvironmentServiceError.invalidServerURL(value)
        }

        guard scheme == "http" || scheme == "https" else {
            throw AppServerEnvironmentServiceError.unsupportedServerURLScheme(scheme)
        }

        if scheme == "http", !isLocalHost(host) {
            throw AppServerEnvironmentServiceError.insecureServerURL
        }

        guard components.user == nil,
              components.password == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil
        else {
            throw AppServerEnvironmentServiceError.serverURLMustBeRoot
        }

        components.scheme = scheme
        components.host = host.lowercased()
        components.path = ""
        if (scheme == "http" && components.port == 80) ||
            (scheme == "https" && components.port == 443)
        {
            components.port = nil
        }

        guard let url = components.url else {
            throw AppServerEnvironmentServiceError.invalidServerURL(value)
        }

        return url
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let addressComponents = host.split(separator: ".", omittingEmptySubsequences: false)
        let isIPv4Loopback = addressComponents.count == 4 &&
            addressComponents.first == "127" &&
            addressComponents.allSatisfy { UInt8($0) != nil }
        return host == "localhost" ||
            isIPv4Loopback ||
            host == "::1"
    }
}
