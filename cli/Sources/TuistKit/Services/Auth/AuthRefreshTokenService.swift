import Foundation
import TuistServer
import FileSystem
import Path

enum AuthRefreshTokenServiceError: Equatable, LocalizedError {
    case invalidServerURL(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidServerURL(let url):
            return "The server URL \(url) is not a valid URL."
        }
    }
}

struct AuthRefreshTokenService {
    let serverAuthenticationController: ServerAuthenticationControlling
    let fileSystem: FileSystem
    
    public init(serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(), fileSystem: FileSystem = FileSystem()) {
        self.serverAuthenticationController = serverAuthenticationController
        self.fileSystem = fileSystem
    }
    
    func run(serverURL: String, lockFilePath: String) async throws {
        guard let url = URL.init(string: serverURL) else {  throw AuthRefreshTokenServiceError.invalidServerURL(serverURL) }
        try await serverAuthenticationController.refreshToken(serverURL: url)
        let path = try AbsolutePath(validating: lockFilePath)
        if try await fileSystem.exists(path) {
            try await fileSystem.remove(path)
        }
    }
    
}
