import Foundation
import Mockable
import Path
import TuistSupport

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

@Mockable
public protocol ServerCredentialsStoring: Sendable {
    /// It stores the credentials for the server with the given URL.
    /// - Parameters:
    ///   - credentials: Credentials to be stored.
    ///   - serverURL: Server URL (without path).
    func store(credentials: ServerCredentials, serverURL: URL) throws

    /// Gets the credentials to authenticate the user against the server with the given URL. Throws an error if credentials are
    /// not found.
    /// - Parameter serverURL: Server URL (without path).
    func get(serverURL: URL) throws -> ServerCredentials

    /// Reads the credentials to authenticate the user against the server with the given URL.
    /// - Parameter serverURL: Server URL (without path).
    func read(serverURL: URL) throws -> ServerCredentials?

    /// Deletes the credentials for the server with the given URL.
    /// - Parameter serverURL: Server URL (without path).
    func delete(serverURL: URL) throws
}

enum ServerCredentialsStoreError: FatalError {
    case credentialsNotFound
    case xcdgHomePathNotAbsolute(String)
    case invalidServerURL(String)

    var description: String {
        switch self {
        case .credentialsNotFound:
            return "You are not authenticated. Authenticate by running `tuist auth`."
        case let .xcdgHomePathNotAbsolute(path):
            return "We expected the value of the XDG_CONFIG_HOME environment variable, \(path), to be an absolute path but it's not."
        case let .invalidServerURL(url):
            return "We couldn't obtain the host from the following URL because it seems invalid \(url)"
        }
    }

    var type: ErrorType {
        switch self {
        case .credentialsNotFound:
            return .abort
        case .xcdgHomePathNotAbsolute:
            return .abort
        case .invalidServerURL:
            return .abort
        }
    }
}

public final class ServerCredentialsStore: ServerCredentialsStoring {
    private let fileHandler: FileHandling
    private let configDirectory: AbsolutePath?

    /// Default initializer.
    public convenience init() {
        self.init(fileHandler: FileHandler.shared)
    }

    init(fileHandler: FileHandling, configDirectory: AbsolutePath? = nil) {
        self.fileHandler = fileHandler
        self.configDirectory = configDirectory
    }

    // MARK: - CredentialsStoring

    public func store(credentials: ServerCredentials, serverURL: URL) throws {
        let path = try credentialsFilePath(serverURL: serverURL)
        let data = try JSONEncoder().encode(credentials)
        if !fileHandler.exists(path.parentDirectory) {
            try fileHandler.createFolder(path.parentDirectory)
        }
        try data.write(to: path.url, options: .atomic)
    }

    public func read(serverURL: URL) throws -> ServerCredentials? {
        let path = try credentialsFilePath(serverURL: serverURL)
        guard fileHandler.exists(path) else { return nil }
        let data = try fileHandler.readFile(path)

        /**
         This might fail if we've migrated the schema, which is very unlikely, or if someone modifies the content in it
         and the new schema doesn't align with the one that we expect. We could add logic to handle those gracefully,
         but since the user can recover from it by signing in again, I think it's ok not to add more complexity here.
         */
        return try? JSONDecoder().decode(ServerCredentials.self, from: data)
    }

    public func get(serverURL: URL) throws -> ServerCredentials {
        guard let credentials = try read(serverURL: serverURL)
        else {
            throw ServerCredentialsStoreError.credentialsNotFound
        }

        return credentials
    }

    public func delete(serverURL: URL) throws {
        let path = try credentialsFilePath(serverURL: serverURL)
        if fileHandler.exists(path) {
            try fileHandler.delete(path)
        }
    }

    // MARK: - Fileprivate

    fileprivate static func configDirectory() throws -> AbsolutePath {
        var directory: AbsolutePath!

        if let xdgConfigHomeString = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            do {
                directory = try AbsolutePath(validating: xdgConfigHomeString)
            } catch {
                throw ServerCredentialsStoreError.xcdgHomePathNotAbsolute(xdgConfigHomeString)
            }
        }

        if directory == nil {
            directory = FileHandler.shared.homeDirectory.appending(component: ".config")
        }
        return directory.appending(component: "tuist")
    }

    fileprivate func credentialsFilePath(serverURL: URL) throws -> AbsolutePath {
        guard let components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false), let host = components.host else {
            throw ServerCredentialsStoreError.invalidServerURL(serverURL.absoluteString)
        }
        let directory = if let configDirectory {
            configDirectory
        } else {
            try ServerCredentialsStore.configDirectory()
        }
        // swiftlint:disable:next force_try
        return directory.appending(try! RelativePath(validating: "credentials/\(host).json"))
    }
}
