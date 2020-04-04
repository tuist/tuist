import Basic
@testable import TuistSigning

final class MockSigningFilesLocator: SigningFilesLocating {
    var locateEncryptedSigningFilesStub: ((AbsolutePath) throws -> [AbsolutePath])?
    var locateUnencryptedSigningFilesStub: ((AbsolutePath) throws -> [AbsolutePath])?

    func locateEncryptedSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath] {
        try locateEncryptedSigningFilesStub?(path) ?? []
    }

    func locateUnencryptedSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath] {
        try locateUnencryptedSigningFilesStub?(path) ?? []
    }
}
