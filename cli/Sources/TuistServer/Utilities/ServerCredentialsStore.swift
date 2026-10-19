import FileSystem
import Foundation
#if !os(Linux)
    import KeychainAccess
#endif
#if canImport(TuistEnvironment)
    import TuistEnvironment
#endif
#if canImport(TuistSupport)
    import TuistSupport
#endif
import Mockable
import Path

public struct ServerCredentials: Sendable, Codable, Equatable {
    /// JWT access token
    public let accessToken: String

    /// JWT refresh token
    public let refreshToken: String?

    /// The OAuth client that issued this token pair. Absent for legacy and API-auth credentials.
    public let oauthClientID: String?

    /// A rejected refresh must remain distinguishable from explicitly signed out.
    public let rejected: Bool?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        oauthClientID: String? = nil,
        rejected: Bool? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.oauthClientID = oauthClientID
        self.rejected = rejected
    }

    #if DEBUG
        public static func test(
            accessToken: String = "access-token",
            refreshToken: String? = "refresh-token",
            oauthClientID: String? = nil
        ) -> ServerCredentials {
            return ServerCredentials(accessToken: accessToken, refreshToken: refreshToken, oauthClientID: oauthClientID)
        }
    #endif
}

@Mockable
public protocol ServerCredentialsStoring: Sendable {
    /// It stores the credentials for the server with the given URL.
    /// - Parameters:
    ///   - credentials: Credentials to be stored.
    ///   - serverURL: Server URL (without path).
    func store(credentials: ServerCredentials, serverURL: URL) async throws

    /// Gets the credentials to authenticate the user against the server with the given URL. Throws an error if credentials are
    /// not found.
    /// - Parameter serverURL: Server URL (without path).
    func get(serverURL: URL) async throws -> ServerCredentials

    /// Reads the credentials to authenticate the user against the server with the given URL.
    /// - Parameter serverURL: Server URL (without path).
    func read(serverURL: URL) async throws -> ServerCredentials?

    /// Deletes the credentials for the server with the given URL.
    /// - Parameter serverURL: Server URL (without path).
    func delete(serverURL: URL) async throws

    /// Stream of server credentials triggered whenever the credentials change.
    var credentialsChanged: AsyncStream<ServerCredentials?> { get }
}

private enum CredentialFileLocator {
    static func canonicalURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = components.host else {
            throw ServerCredentialsStoreError.invalidServerURL(url.absoluteString)
        }
        components.host = normalizedHost(host)
        guard let canonical = components.url else { throw ServerCredentialsStoreError.invalidServerURL(url.absoluteString) }
        return canonical
    }

    static func normalizedHost(_ host: String) -> String {
        var value = host.lowercased()
        while value.hasSuffix(".") {
            value.removeLast()
        }
        return value
    }

    static func paths(defaultPath: AbsolutePath, fileSystem: FileSysteming) async throws -> [AbsolutePath] {
        guard try await fileSystem.exists(defaultPath.parentDirectory) else { return [defaultPath] }
        let host = normalizedHost(defaultPath.basenameWithoutExt)
        let files = try await fileSystem.glob(directory: defaultPath.parentDirectory, include: ["*.json"]).collect()
        let aliases = files.filter { normalizedHost($0.basenameWithoutExt) == host && $0 != defaultPath }
            .sorted { $0.pathString < $1.pathString }
        if try await fileSystem.exists(defaultPath) { return [defaultPath] + aliases }
        return aliases.isEmpty ? [defaultPath] : aliases
    }
}

enum ServerCredentialsStoreError: LocalizedError {
    case credentialsNotFound
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            return "You are not authenticated. Authenticate by running 'tuist auth login'."
        case let .invalidServerURL(url):
            return "We couldn't obtain the host from the following URL because it seems invalid \(url)"
        }
    }
}

public enum ServerCredentialsStoreBackend: Sendable {
    #if os(Linux)
        case fileSystem
    #else
        #if os(macOS)
            case fileSystem
        #endif
        case keychain
    #endif
}

#if !os(Linux)
    public final class ServerCredentialsStore: ServerCredentialsStoring, ObservableObject {
        #if os(macOS)
            @TaskLocal public static var current: ServerCredentialsStoring = ServerCredentialsStore(backend: .fileSystem)
        #else
            @TaskLocal public static var current: ServerCredentialsStoring = ServerCredentialsStore(backend: .keychain)
        #endif

        private let backend: ServerCredentialsStoreBackend
        private let fileSystem: FileSysteming
        private let configDirectory: AbsolutePath?
        private let credentialsChangedContinuation = AsyncStream<ServerCredentials?>.makeStream()

        public var credentialsChanged: AsyncStream<ServerCredentials?> {
            credentialsChangedContinuation.stream
        }

        public init(
            backend: ServerCredentialsStoreBackend,
            fileSystem: FileSysteming = FileSystem(),
            configDirectory: AbsolutePath? = nil
        ) {
            self.backend = backend
            self.configDirectory = configDirectory
            self.fileSystem = fileSystem
        }

        // MARK: - CredentialsStoring

        public func store(credentials: ServerCredentials, serverURL: URL) async throws {
            switch backend {
            case .keychain:
                let serverURL = try CredentialFileLocator.canonicalURL(serverURL)
                if credentials.rejected == true {
                    try keychain(serverURL: serverURL).set("true", key: serverURL.absoluteString + "_rejected")
                } else {
                    try keychain(serverURL: serverURL).remove(serverURL.absoluteString + "_rejected")
                }
                if let oauthClientID = credentials.oauthClientID {
                    try keychain(serverURL: serverURL).set(oauthClientID, key: serverURL.absoluteString + "_oauth_client_id")
                } else {
                    try keychain(serverURL: serverURL).remove(serverURL.absoluteString + "_oauth_client_id")
                }
                if let refreshToken = credentials.refreshToken {
                    try keychain(serverURL: serverURL)
                        .comment("Refresh token against \(serverURL.absoluteString)")
                        .set(refreshToken, key: serverURL.absoluteString + "_refresh_token")
                }
                try keychain(serverURL: serverURL)
                    .comment("Refresh token against \(serverURL.absoluteString)")
                    .set(credentials.accessToken, key: serverURL.absoluteString + "_access_token")
            #if os(macOS)
                case .fileSystem:
                    let path = try credentialsFilePath(serverURL: serverURL)
                    let data = try JSONEncoder().encode(credentials)
                    if try await !fileSystem.exists(path.parentDirectory) {
                        try await fileSystem.makeDirectory(at: path.parentDirectory)
                    }
                    try data.write(to: URL(fileURLWithPath: path.pathString), options: .atomic)
            #endif
            }

            credentialsChangedContinuation.continuation.yield(credentials)
        }

        public func read(serverURL: URL) async throws -> ServerCredentials? {
            switch backend {
            case .keychain:
                for candidate in [try CredentialFileLocator.canonicalURL(serverURL), serverURL] {
                    guard let accessToken = try keychain(serverURL: candidate).get(candidate.absoluteString + "_access_token")
                    else { continue }
                    return ServerCredentials(
                        accessToken: accessToken,
                        refreshToken: try keychain(serverURL: candidate).get(candidate.absoluteString + "_refresh_token"),
                        oauthClientID: try keychain(serverURL: candidate).get(candidate.absoluteString + "_oauth_client_id"),
                        rejected: try keychain(serverURL: candidate).get(candidate.absoluteString + "_rejected") == "true"
                    )
                }
                return nil
            #if os(macOS)
                case .fileSystem:
                    let paths = try await CredentialFileLocator.paths(
                        defaultPath: credentialsFilePath(serverURL: serverURL),
                        fileSystem: fileSystem
                    )
                    let path = paths[0]
                    guard try await fileSystem.exists(path) else { return nil }
                    let data = try await fileSystem.readFile(at: path)

                    if ServerReportPublishingMode.enabled {
                        do {
                            return try JSONDecoder().decode(ServerCredentials.self, from: data)
                        } catch {
                            throw ServerReportPublishingError.invalidCredentials
                        }
                    }
                    return try? JSONDecoder().decode(ServerCredentials.self, from: data)
            #endif
            }
        }

        public func get(serverURL: URL) async throws -> ServerCredentials {
            guard let credentials = try await read(serverURL: serverURL)
            else {
                throw ServerCredentialsStoreError.credentialsNotFound
            }

            return credentials
        }

        public func delete(serverURL: URL) async throws {
            switch backend {
            case .keychain:
                for candidate in Set([try CredentialFileLocator.canonicalURL(serverURL), serverURL]) {
                    let keychain = keychain(serverURL: candidate)
                    try keychain.remove(candidate.absoluteString + "_refresh_token")
                    try keychain.remove(candidate.absoluteString + "_access_token")
                    try keychain.remove(candidate.absoluteString + "_oauth_client_id")
                    try keychain.remove(candidate.absoluteString + "_rejected")
                }
            #if os(macOS)
                case .fileSystem:
                    for path in try await CredentialFileLocator.paths(
                        defaultPath: credentialsFilePath(serverURL: serverURL),
                        fileSystem: fileSystem
                    ) where try await fileSystem.exists(path) {
                        try await fileSystem.remove(path)
                    }
            #endif
            }

            credentialsChangedContinuation.continuation.yield(nil)
        }

        #if os(macOS)
            fileprivate func credentialsFilePath(serverURL: URL) throws -> AbsolutePath {
                guard let components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
                      let host = components.host
                else {
                    throw ServerCredentialsStoreError.invalidServerURL(serverURL.absoluteString)
                }
                let directory = if let configDirectory {
                    configDirectory
                } else {
                    Environment.current.configDirectory
                }
                return try directory
                    .appending(RelativePath(validating: "credentials/\(CredentialFileLocator.normalizedHost(host)).json"))
            }
        #endif

        fileprivate func keychain(serverURL: URL) -> Keychain {
            Keychain(server: serverURL, protocolType: .https, authenticationType: .default)
                .synchronizable(false)
                .label("\(serverURL.absoluteString)")
        }

        #if DEBUG
            public static var mocked: MockServerCredentialsStoring? { current as? MockServerCredentialsStoring }
        #endif
    }
#else
    public final class ServerCredentialsStore: ServerCredentialsStoring {
        @TaskLocal public static var current: ServerCredentialsStoring = ServerCredentialsStore(
            backend: .fileSystem,
            configDirectory: defaultConfigDirectory()
        )

        private let backend: ServerCredentialsStoreBackend
        private let fileSystem: FileSysteming
        private let configDirectory: AbsolutePath
        private let credentialsChangedContinuation = AsyncStream<ServerCredentials?>.makeStream()

        public var credentialsChanged: AsyncStream<ServerCredentials?> {
            credentialsChangedContinuation.stream
        }

        public init(
            backend: ServerCredentialsStoreBackend,
            fileSystem: FileSysteming = FileSystem(),
            configDirectory: AbsolutePath
        ) {
            self.backend = backend
            self.configDirectory = configDirectory
            self.fileSystem = fileSystem
        }

        private static func defaultConfigDirectory() -> AbsolutePath {
            let homeDirectory = ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"
            // swiftlint:disable:next force_try
            return try! AbsolutePath(validating: homeDirectory).appending(component: ".config").appending(component: "tuist")
        }

        // MARK: - CredentialsStoring

        public func store(credentials: ServerCredentials, serverURL: URL) async throws {
            switch backend {
            case .fileSystem:
                let path = try credentialsFilePath(serverURL: serverURL)
                let data = try JSONEncoder().encode(credentials)
                if try await !fileSystem.exists(path.parentDirectory) {
                    try await fileSystem.makeDirectory(at: path.parentDirectory)
                }
                try data.write(to: URL(fileURLWithPath: path.pathString), options: .atomic)
            }

            credentialsChangedContinuation.continuation.yield(credentials)
        }

        public func read(serverURL: URL) async throws -> ServerCredentials? {
            switch backend {
            case .fileSystem:
                let paths = try await CredentialFileLocator.paths(
                    defaultPath: credentialsFilePath(serverURL: serverURL),
                    fileSystem: fileSystem
                )
                let path = paths[0]
                guard try await fileSystem.exists(path) else { return nil }
                let data = try await fileSystem.readFile(at: path)

                if ServerReportPublishingMode.enabled {
                    do {
                        return try JSONDecoder().decode(ServerCredentials.self, from: data)
                    } catch {
                        throw ServerReportPublishingError.invalidCredentials
                    }
                }
                return try? JSONDecoder().decode(ServerCredentials.self, from: data)
            }
        }

        public func get(serverURL: URL) async throws -> ServerCredentials {
            guard let credentials = try await read(serverURL: serverURL)
            else {
                throw ServerCredentialsStoreError.credentialsNotFound
            }

            return credentials
        }

        public func delete(serverURL: URL) async throws {
            switch backend {
            case .fileSystem:
                for path in try await CredentialFileLocator.paths(
                    defaultPath: credentialsFilePath(serverURL: serverURL),
                    fileSystem: fileSystem
                ) where try await fileSystem.exists(path) {
                    try await fileSystem.remove(path)
                }
            }

            credentialsChangedContinuation.continuation.yield(nil)
        }

        fileprivate func credentialsFilePath(serverURL: URL) throws -> AbsolutePath {
            guard let components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
                  let host = components.host
            else {
                throw ServerCredentialsStoreError.invalidServerURL(serverURL.absoluteString)
            }
            return try configDirectory
                .appending(RelativePath(validating: "credentials/\(CredentialFileLocator.normalizedHost(host)).json"))
        }

        #if DEBUG
            public static var mocked: MockServerCredentialsStoring? { current as? MockServerCredentialsStoring }
        #endif
    }
#endif
