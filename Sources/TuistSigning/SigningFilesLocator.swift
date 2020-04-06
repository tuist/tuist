import Basic
import TuistCore
import TuistSupport

enum SigningFilesLocatorError: FatalError {
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
    func hasSigningDirectory(at path: AbsolutePath) throws -> Bool
    func locateEncryptedSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath]
    func locateUnencryptedSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath]
}

final class SigningFilesLocator: SigningFilesLocating {
    private let rootDirectoryLocator: RootDirectoryLocating

    init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }
    
    func hasSigningDirectory(at path: AbsolutePath) throws -> Bool {
        guard
            let rootDirectory = rootDirectoryLocator.locate(from: path)
        else { throw SigningFilesLocatorError.signingDirectoryNotFound(path) }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        return FileHandler.shared.exists(signingDirectory)
    }

    func locateEncryptedSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath] {
        guard
            let rootDirectory = rootDirectoryLocator.locate(from: path)
        else { throw SigningFilesLocatorError.signingDirectoryNotFound(path) }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        return FileHandler.shared.glob(signingDirectory, glob: "*").filter { $0.extension == Constants.encryptedExtension }
    }

    func locateUnencryptedSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath] {
        guard
            let rootDirectory = rootDirectoryLocator.locate(from: path)
        else { throw SigningFilesLocatorError.signingDirectoryNotFound(path) }
        let signingDirectory = rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.signingDirectoryName)
        return FileHandler.shared.glob(signingDirectory, glob: "*").filter { $0.extension != Constants.encryptedExtension }
    }
}
