import TSCBasic
@testable import TuistSigning

final class MockSigningCipher: SigningCiphering {
    var decryptCertificatesStub: ((AbsolutePath, Bool) throws -> Void)?
    var encryptCertificatesStub: ((AbsolutePath, Bool) throws -> Void)?

    func decryptCertificates(at path: AbsolutePath, keepFiles: Bool) throws {
        try decryptCertificatesStub?(path, keepFiles)
    }

    func encryptCertificates(at path: AbsolutePath, keepFiles: Bool) throws {
        try encryptCertificatesStub?(path, keepFiles)
    }
}
