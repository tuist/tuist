import Foundation
import TuistCloud

public final class MockListProjectsService: ListProjectsServicing {
    public init() {}

    public func listProjects(serverURL: URL) async throws -> [TuistCloud.CloudProject] {
        try await listProjectsStub?(serverURL, nil, nil) ?? []
    }

    public var listProjectsStub: ((URL, String?, String?) async throws -> [CloudProject])?
    public func listProjects(
        serverURL: URL,
        accountName: String?,
        projectName: String?
    ) async throws -> [CloudProject] {
        try await listProjectsStub?(serverURL, accountName, projectName) ?? []
    }
}
