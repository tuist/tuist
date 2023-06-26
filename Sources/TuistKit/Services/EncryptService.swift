import Foundation
import TSCBasic
import TuistCore
import TuistSigning
import TuistSupport

public final class EncryptService {
    private let signingCipher: SigningCiphering
    
    public convenience init() {
        self.init(signingCipher: SigningCipher())
    }

    init(signingCipher: SigningCiphering) {
        self.signingCipher = signingCipher
    }

    public func run(path: String?) throws {
        let path = try self.path(path)
        try signingCipher.encryptSigning(at: path, keepFiles: false)

        logger.notice("Successfully encrypted all signing files", metadata: .success)
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
