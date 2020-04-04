import Basic
@testable import TuistSigning

final class MockSigningFilesLocator: SigningFilesLocating {
    var locateSigningFilesStub: ((AbsolutePath) throws -> [AbsolutePath])?
    
    func locateSigningFiles(at path: AbsolutePath) throws -> [AbsolutePath] {
        try locateSigningFilesStub?(path) ?? []
    }
}
