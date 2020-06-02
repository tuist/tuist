import TSCBasic
import TuistCore
import TuistSupport

enum SigningFilesLocatorError: FatalError, Equatable {
    case signingDirectoryNotFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .signingDirectoryNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .signingDirectoryNotFound(fromPath):
            return "Could not find signing directory from \(fromPath.pathString)"
        }
    }
}

protocol SigningFilesLocating {
    func locateSigningDirectory(from path: AbsolutePath) throws -> AbsolutePath?
    func locateProvisioningProfiles(from path: AbsolutePath) throws -> [AbsolutePath]
    func locateUnencryptedCertificates(from path: AbsolutePath) throws -> [AbsolutePath]
    func locateEncryptedCertificates(from path: AbsolutePath) throws -> [AbsolutePath]
    func locateUnencryptedPrivateKeys(from path: AbsolutePath) throws -> [AbsolutePath]
    func locateEncryptedPrivateKeys(from path: AbsolutePath) throws -> [AbsolutePath]
}

final class SigningFilesLocator: SigningFilesLocating {
    private let rootDirectoryLocator: RootDirectoryLocating

    init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }
    
    func locateSigningDirectory(from path: AbsolutePath) throws -> AbsolutePath? {
        guard
            let rootDirectory = rootDirectoryLocator.locate(from: path)
        else { throw SigningFilesLocatorError.signingDirectoryNotFound(path) }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        return FileHandler.shared.exists(signingDirectory) ? signingDirectory : nil
    }
    
    func locateProvisioningProfiles(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateSigningFiles(at: path)
            .filter { $0.extension == "mobileprovision" || $0.extension == "provisionprofile"  }
    }
    
    func locateUnencryptedCertificates(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateSigningFiles(at: path)
            .filter { $0.extension == "cer" }
    }
    
    func locateEncryptedCertificates(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateSigningFiles(at: path)
            .filter { $0.pathString.hasSuffix("cer.encrypted") }
    }
    
    func locateUnencryptedPrivateKeys(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateSigningFiles(at: path)
            .filter { $0.extension == "p12" }
    }
    
    func locateEncryptedPrivateKeys(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateSigningFiles(at: path)
            .filter { $0.pathString.hasSuffix("p12.encrypted") }
    }
    
    // MARK: - Helpers
    
    private func locateSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath] {
        guard
            let rootDirectory = rootDirectoryLocator.locate(from: path)
        else { throw SigningFilesLocatorError.signingDirectoryNotFound(path) }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        return FileHandler.shared.glob(signingDirectory, glob: "*")
    }
}
