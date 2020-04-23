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
        let path = self.path(path)
        try signingCipher.decryptSigning(at: path, keepFiles: false)
        logger.notice("Successfully decrypted all signing files", metadata: .success)
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
