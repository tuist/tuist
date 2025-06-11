import FileSystem
import Foundation
import Mockable
import Path
#if canImport(TuistSupport)
    import TuistSupport
#endif

public struct ServerCredentials: Codable, Equatable {
    /// Deprecated authentication token.
    public let token: String?

    /// JWT access token
    public let accessToken: String?

    /// JWT refresh token
    public let refreshToken: String?

    /// Initializes the credentials with its attributes.
    /// - Parameters:
    ///   - token: Authentication token.
    ///   - account: Account identifier.
    public init(
        token: String?,
        accessToken: String?,
        refreshToken: String?
    ) {
        self.token = token
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

#if DEBUG
    extension ServerCredentials {
        public static func test(
            token: String? = nil,
            accessToken: String? = nil,
            refreshToken: String? = nil
        ) -> ServerCredentials {
            return ServerCredentials(token: token, accessToken: accessToken, refreshToken: refreshToken)
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

public struct ServerCredentialsStore: ServerCredentialsStoring {
    private let fileSystem: FileSysteming
    private let configDirectory: AbsolutePath?

    public init(
        fileSystem: FileSysteming = FileSystem(),
        configDirectory: AbsolutePath? = nil
    ) {
        self.configDirectory = configDirectory
        self.fileSystem = fileSystem
    }

    // MARK: - CredentialsStoring

    public func store(credentials: ServerCredentials, serverURL: URL) async throws {
        #if canImport(TuistSupport)
            let path = try credentialsFilePath(serverURL: serverURL)
            let data = try JSONEncoder().encode(credentials)
            if try await !fileSystem.exists(path.parentDirectory) {
                try await fileSystem.makeDirectory(at: path.parentDirectory)
            }
            try data.write(to: path.url, options: .atomic)
        #endif
    }

    public func read(serverURL: URL) async throws -> ServerCredentials? {
        let path = try credentialsFilePath(serverURL: serverURL)
        guard try await fileSystem.exists(path) else { return nil }
        let data = try await fileSystem.readFile(at: path)

        // This might fail if we've migrated the schema, which is very unlikely, or if someone modifies the content in it
        // and the new schema doesn't align with the one that we expect. We could add logic to handle those gracefully,
        // but since the user can recover from it by signing in again, I think it's ok not to add more complexity here.
        return try? JSONDecoder().decode(ServerCredentials.self, from: data)
    }

    public func get(serverURL: URL) async throws -> ServerCredentials {
        guard let credentials = try await read(serverURL: serverURL)
        else {
            throw ServerCredentialsStoreError.credentialsNotFound
        }

        return credentials
    }

    public func delete(serverURL: URL) async throws {
        let path = try credentialsFilePath(serverURL: serverURL)
        if try await fileSystem.exists(path) {
            try await fileSystem.remove(path)
        }
    }

    fileprivate func credentialsFilePath(serverURL: URL) throws -> AbsolutePath {
        guard let components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false), let host = components.host else {
            throw ServerCredentialsStoreError.invalidServerURL(serverURL.absoluteString)
        }
        let directory = if let configDirectory {
            configDirectory
        } else {
            #if canImport(TuistSupport)
                Environment.current.configDirectory
            #else
                fatalError("Can't obtain the configuration directory for the current destination.")
            #endif
        }
        // swiftlint:disable:next force_try
        return directory.appending(try! RelativePath(validating: "credentials/\(host).json"))
    }
}
