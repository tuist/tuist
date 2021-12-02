import TSCBasic
import TuistCore
@testable import TuistSigning

final class MockSigningMatcher: SigningMatching {
    var matchStub: (
        (AbsolutePath) throws
            -> (certificates: [String: Certificate], provisioningProfiles: [String: [String: ProvisioningProfile]])
    )?
    func match(from path: AbsolutePath) throws
        -> (certificates: [String: Certificate], provisioningProfiles: [String: [String: ProvisioningProfile]])
    {
        try matchStub?(path) ?? (certificates: [:], provisioningProfiles: [:])
    }
}
