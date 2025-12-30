import FileSystem
import Foundation
import KeychainAccess
import Mockable
import Path
#if canImport(TuistSupport)
    import TuistSupport
#endif

public struct ServerCredentials: Sendable, Codable, Equatable {
    /// JWT access token
    public let accessToken: String

    /// JWT refresh token
    public let refreshToken: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

#if DEBUG
    extension ServerCredentials {
        public static func test(
            accessToken: String = "access-token",
            refreshToken: String? = "refresh-token"
        ) -> ServerCredentials {
            return ServerCredentials(accessToken: accessToken, refreshToken: refreshToken)
        }
    }
#endif

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
    #if os(macOS) || os(Linux) || os(Windows)
        case fileSystem
    #endif
    case keychain
}

public final class ServerCredentialsStore: ServerCredentialsStoring, ObservableObject {
    #if os(macOS) || os(Linux) || os(Windows)
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
            if let refreshToken = credentials.refreshToken {
                try keychain(serverURL: serverURL)
                    .comment("Refresh token against \(serverURL.absoluteString)")
                    .set(refreshToken, key: serverURL.absoluteString + "_refresh_token")
            }
            try keychain(serverURL: serverURL)
                .comment("Refresh token against \(serverURL.absoluteString)")
                .set(credentials.accessToken, key: serverURL.absoluteString + "_access_token")
        #if os(macOS) || os(Linux) || os(Windows)
            case .fileSystem:
                let path = try credentialsFilePath(serverURL: serverURL)
                let data = try JSONEncoder().encode(credentials)
                if try await !fileSystem.exists(path.parentDirectory) {
                    try await fileSystem.makeDirectory(at: path.parentDirectory)
                }
                try data.write(to: path.url, options: .atomic)
        #endif
        }

        credentialsChangedContinuation.continuation.yield(credentials)
    }

    public func read(serverURL: URL) async throws -> ServerCredentials? {
        switch backend {
        case .keychain:
            let refreshToken = try keychain(serverURL: serverURL).get(serverURL.absoluteString + "_refresh_token")!
            let accessToken = try keychain(serverURL: serverURL).get(serverURL.absoluteString + "_access_token")!
            return ServerCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken
            )
        #if os(macOS) || os(Linux) || os(Windows)
            case .fileSystem:
                let path = try credentialsFilePath(serverURL: serverURL)
                guard try await fileSystem.exists(path) else { return nil }
                let data = try await fileSystem.readFile(at: path)

                // This might fail if we've migrated the schema, which is very unlikely, or if someone modifies the content in it
                // and the new schema doesn't align with the one that we expect. We could add logic to handle those gracefully,
                // but since the user can recover from it by signing in again, I think it's ok not to add more complexity here.
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
            let keychain = keychain(serverURL: serverURL)
            try keychain.remove(serverURL.absoluteString + "_refresh_token")
            try keychain.remove(serverURL.absoluteString + "_access_token")
        #if os(macOS) || os(Linux) || os(Windows)
            case .fileSystem:
                let path = try credentialsFilePath(serverURL: serverURL)
                if try await fileSystem.exists(path) {
                    try await fileSystem.remove(path)
                }
        #endif
        }

        credentialsChangedContinuation.continuation.yield(nil)
    }

    fileprivate func credentialsFilePath(serverURL: URL) throws -> AbsolutePath {
        guard let components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false), let host = components.host else {
            throw ServerCredentialsStoreError.invalidServerURL(serverURL.absoluteString)
        }
        let directory = if let configDirectory {
            configDirectory
        } else {
            #if os(macOS) || os(Linux) || os(Windows)
                Environment.current.configDirectory
            #else
                fatalError("Can't obtain the configuration directory for the current destination.")
            #endif
        }
        // swiftlint:disable:next force_try
        return directory.appending(try! RelativePath(validating: "credentials/\(host).json"))
    }

    fileprivate func keychain(serverURL: URL) -> Keychain {
        Keychain(server: serverURL, protocolType: .https, authenticationType: .default)
            .synchronizable(false)
            .label("\(serverURL.absoluteString)")
    }
}

#if DEBUG
    extension ServerCredentialsStore {
        public static var mocked: MockServerCredentialsStoring? { current as? MockServerCredentialsStoring }
    }
#endif
