import Foundation
import TuistCloud

public final class MockGetOrganizationService: GetOrganizationServicing {
    public init() {}

    public var getOrganizationStub: ((String, URL) async throws -> CloudOrganization)?
    public func getOrganization(
        organizationName: String,
        serverURL: URL
    ) async throws -> CloudOrganization {
        try await getOrganizationStub?(organizationName, serverURL) ?? .test()
    }
}
