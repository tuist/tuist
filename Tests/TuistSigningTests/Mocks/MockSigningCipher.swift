import Basic
@testable import TuistSigning

final class MockSigningCipher: SigningCiphering {
    var decryptSigningStub: ((AbsolutePath, Bool) throws -> Void)?
    var encryptSigningStub: ((AbsolutePath, Bool) throws -> Void)?

    func decryptSigning(at path: AbsolutePath, keepFiles: Bool) throws {
        try decryptSigningStub?(path, keepFiles)
    }

    func encryptSigning(at path: AbsolutePath, keepFiles: Bool) throws {
        try encryptSigningStub?(path, keepFiles)
    }
}
