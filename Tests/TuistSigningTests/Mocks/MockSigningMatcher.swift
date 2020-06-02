import TSCBasic
import TuistCore
@testable import TuistSigning

final class MockSigningMatcher: SigningMatching {
    var matchStub: ((Graph) throws -> (certificates: [String : Certificate], provisioningProfiles: [String : [String : ProvisioningProfile]]))?
    func match(graph: Graph) throws -> (certificates: [String : Certificate], provisioningProfiles: [String : [String : ProvisioningProfile]]) {
        try matchStub?(graph) ?? (certificates: [:], provisioningProfiles: [:])
    }
}
