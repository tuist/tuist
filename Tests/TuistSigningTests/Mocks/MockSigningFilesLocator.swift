import TSCBasic
@testable import TuistSigning

final class MockSigningFilesLocator: SigningFilesLocating {
    var locateSigningDirectoryStub: ((AbsolutePath) throws -> AbsolutePath)?
    func locateSigningDirectory(from path: AbsolutePath) throws -> AbsolutePath? {
        try locateSigningDirectoryStub?(path)
    }

    var locateProvisioningProfilesStub: ((AbsolutePath) throws -> [AbsolutePath])?
    func locateProvisioningProfiles(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateProvisioningProfilesStub?(path) ?? []
    }

    var locateUnencryptedCertificatesStub: ((AbsolutePath) throws -> [AbsolutePath])?
    func locateUnencryptedCertificates(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateUnencryptedCertificatesStub?(path) ?? []
    }

    var locateEncryptedCertificatesStub: ((AbsolutePath) throws -> [AbsolutePath])?
    func locateEncryptedCertificates(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateEncryptedCertificatesStub?(path) ?? []
    }

    var locateUnencryptedPrivateKeysStub: ((AbsolutePath) throws -> [AbsolutePath])?
    func locateUnencryptedPrivateKeys(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateUnencryptedPrivateKeysStub?(path) ?? []
    }

    var locateEncryptedPrivateKeysStub: ((AbsolutePath) throws -> [AbsolutePath])?
    func locateEncryptedPrivateKeys(from path: AbsolutePath) throws -> [AbsolutePath] {
        try locateEncryptedPrivateKeysStub?(path) ?? []
    }
}
