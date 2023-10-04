import Foundation
import TuistCloud

public final class MockCreateOrganizationInviteService: CreateOrganizationInviteServicing {
    public init() {}

    public var createOrganizationInviteStub: ((String, String, URL) async throws -> CloudInvitation)?
    public func createOrganizationInvite(
        organizationName: String,
        email: String,
        serverURL: URL
    ) async throws -> CloudInvitation {
        try await createOrganizationInviteStub?(organizationName, email, serverURL) ?? .test()
    }
}
