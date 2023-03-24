import Foundation
import TSCBasic
import TuistCore
import TuistSigning
import TuistSupport

final class DecryptService {
    private let signingCipher: SigningCiphering

    init(signingCipher: SigningCiphering = SigningCipher()) {
        self.signingCipher = signingCipher
    }

    func run(path: String?) throws {
        let path = try self.path(path)
        try signingCipher.decryptSigning(at: path, keepFiles: false)
        logger.notice("Successfully decrypted all signing files", metadata: .success)
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path = path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
