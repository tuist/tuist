import TSCBasic
@testable import TuistSigning

final class MockSigningFilesLocator: SigningFilesLocating {
    var hasSigningDirectoryStub: ((AbsolutePath) throws -> Bool)?
    var locateEncryptedSigningFilesStub: ((AbsolutePath) throws -> [AbsolutePath])?
    var locateUnencryptedSigningFilesStub: ((AbsolutePath) throws -> [AbsolutePath])?

    func hasSigningDirectory(at path: AbsolutePath) throws -> Bool {
        try hasSigningDirectoryStub?(path) ?? true
    }

    func locateEncryptedSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath] {
        try locateEncryptedSigningFilesStub?(path) ?? []
    }

    func locateUnencryptedSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath] {
        try locateUnencryptedSigningFilesStub?(path) ?? []
    }
}
