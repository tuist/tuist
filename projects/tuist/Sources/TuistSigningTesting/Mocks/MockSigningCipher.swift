import TSCBasic
@testable import TuistSigning

public final class MockSigningCipher: SigningCiphering {
    public init() {}

    public var readMasterKeyStub: ((AbsolutePath) throws -> String)?
    public func readMasterKey(at path: AbsolutePath) throws -> String {
        try readMasterKeyStub?(path) ?? ""
    }

    public var decryptSigningStub: ((AbsolutePath, Bool) throws -> Void)?
    public func decryptSigning(at path: AbsolutePath, keepFiles: Bool) throws {
        try decryptSigningStub?(path, keepFiles)
    }

    public var encryptSigningStub: ((AbsolutePath, Bool) throws -> Void)?
    public func encryptSigning(at path: AbsolutePath, keepFiles: Bool) throws {
        try encryptSigningStub?(path, keepFiles)
    }
}
