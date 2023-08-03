import Foundation
import TuistCloud

public final class MockListProjectsService: ListProjectsServicing {
    public init() {}

    public var listProjectsStub: ((URL) async throws -> [CloudProject])?
    public func listProjects(serverURL: URL) async throws -> [CloudProject] {
        try await listProjectsStub?(serverURL) ?? []
    }
}
