import TSCBasic
@testable import TuistSigning

final class MockSigningCipher: SigningCiphering {
    var readMasterKeyStub: ((AbsolutePath) throws -> String)?
    func readMasterKey(at path: AbsolutePath) throws -> String {
        try readMasterKeyStub?(path) ?? ""
    }
    
    var decryptSigningStub: ((AbsolutePath, Bool) throws -> Void)?
    func decryptSigning(at path: AbsolutePath, keepFiles: Bool) throws {
        try decryptSigningStub?(path, keepFiles)
    }

    var encryptSigningStub: ((AbsolutePath, Bool) throws -> Void)?
    func encryptSigning(at path: AbsolutePath, keepFiles: Bool) throws {
        try encryptSigningStub?(path, keepFiles)
    }
}
