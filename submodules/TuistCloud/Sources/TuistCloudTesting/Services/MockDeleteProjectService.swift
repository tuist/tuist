import Foundation
import TuistCloud

public final class MockDeleteProjectService: DeleteProjectServicing {
    public init() {}

    public var deleteProjectStub: ((Int, URL) async throws -> Void)?
    public func deleteProject(
        projectId: Int,
        serverURL: URL
    ) async throws {
        try await deleteProjectStub?(projectId, serverURL)
    }
}
