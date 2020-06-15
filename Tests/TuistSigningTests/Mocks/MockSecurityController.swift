import TSCBasic
@testable import TuistSigning

final class MockSecurityController: SecurityControlling {
    var importCertificateStub: ((Certificate, AbsolutePath) throws -> Void)?
    func importCertificate(_ certificate: Certificate, keychainPath: AbsolutePath) throws {
        try importCertificateStub?(certificate, keychainPath)
    }

    var createKeychainStub: ((AbsolutePath, String) throws -> Void)?
    func createKeychain(at path: AbsolutePath, password: String) throws {
        try createKeychainStub?(path, password)
    }

    var unlockKeychainStub: ((AbsolutePath, String) throws -> Void)?
    func unlockKeychain(at path: AbsolutePath, password: String) throws {
        try unlockKeychainStub?(path, password)
    }

    var lockKeychainStub: ((AbsolutePath, String) throws -> Void)?
    func lockKeychain(at path: AbsolutePath, password: String) throws {
        try lockKeychainStub?(path, password)
    }

    var decodeFileStub: ((AbsolutePath) throws -> String)?
    func decodeFile(at path: AbsolutePath) throws -> String {
        try decodeFileStub?(path) ?? ""
    }

    var certificateExistsStub: ((AbsolutePath) throws -> Bool)?
    func certificateExists(path: AbsolutePath) throws -> Bool {
        try certificateExistsStub?(path) ?? false
    }
}
