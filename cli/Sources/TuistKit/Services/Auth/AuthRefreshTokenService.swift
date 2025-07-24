import FileSystem
import Foundation
import Path
import TuistServer
import TuistSupport

enum AuthRefreshTokenServiceError: Equatable, LocalizedError {
    case invalidServerURL(String)
    case tokenRefreshFailed(String)
    case lockFileRemovalFailed(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .invalidServerURL(url):
            return "The server URL \(url) is not a valid URL."
        case let .tokenRefreshFailed(message):
            return "Failed to refresh authentication token: \(message)"
        case let .lockFileRemovalFailed(path):
            return "Failed to remove lock file at \(path.pathString). You may need to remove it manually."
        }
    }
}

struct AuthRefreshTokenService {
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let fileSystem: FileSysteming

    init(
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.fileSystem = fileSystem
    }

    func run(serverURL: String) async throws {
        guard let url = URL(string: serverURL) else {
            throw AuthRefreshTokenServiceError.invalidServerURL(serverURL)
        }
        try await serverAuthenticationController.refreshToken(
            serverURL: url,
            inBackground: false,
            locking: false,
            forceInProcessLock: false
        )
    }
}
