import TSCBasic
@testable import TuistSigning

final class MockProvisioningProfileParser: ProvisioningProfileParsing {
    var parseStub: ((AbsolutePath) throws -> ProvisioningProfile)?
    func parse(at path: AbsolutePath) throws -> ProvisioningProfile {
        try parseStub?(path) ?? ProvisioningProfile.test()
    }
}
