import TSCBasic
@testable import TuistSigning

public final class MockSigningInstaller: SigningInstalling {
    public init() {}

    var installProvisioningProfileStub: ((ProvisioningProfile) throws -> Void)?
    public func installProvisioningProfile(_ provisioningProfile: ProvisioningProfile) throws {
        try installProvisioningProfileStub?(provisioningProfile)
    }

    var installCertificateStub: ((Certificate, AbsolutePath) throws -> Void)?
    public func installCertificate(_ certificate: Certificate, keychainPath: AbsolutePath) throws {
        try installCertificateStub?(certificate, keychainPath)
    }
}
