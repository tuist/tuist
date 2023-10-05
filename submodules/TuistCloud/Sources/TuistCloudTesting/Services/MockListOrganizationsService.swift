import Foundation
import TuistCloud

public final class MockListOrganizationsService: ListOrganizationsServicing {
    public init() {}

    public var listOrganizationsStub: ((URL) async throws -> [CloudOrganization])?
    public func listOrganizations(serverURL: URL) async throws -> [CloudOrganization] {
        try await listOrganizationsStub?(serverURL) ?? []
    }
}
