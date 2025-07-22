import FileSystem
import Foundation
import Path
import TuistServer

enum AuthRefreshTokenServiceError: Equatable, LocalizedError {
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case let .invalidServerURL(url):
            return "The server URL \(url) is not a valid URL."
        }
    }
}

struct AuthRefreshTokenService {
    let serverAuthenticationController: ServerAuthenticationControlling
    let fileSystem: FileSystem

    init(
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        fileSystem: FileSystem = FileSystem()
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.fileSystem = fileSystem
    }

    func run(serverURL: String, lockFilePath: String) async throws {
        guard let url = URL(string: serverURL) else { throw AuthRefreshTokenServiceError.invalidServerURL(serverURL) }
        try await serverAuthenticationController.refreshToken(serverURL: url, inSubprocess: false)
        let path = try AbsolutePath(validating: lockFilePath)
        if try await fileSystem.exists(path) {
            try await fileSystem.remove(path)
        }
    }
}
