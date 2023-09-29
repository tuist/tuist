import Foundation
import TuistCloud

public final class MockCreateProjectService: CreateProjectServicing {
    public init() {}

    public var createProjectStub: ((String, String?, URL) async throws -> CloudProject)?
    public func createProject(name: String, organization: String?, serverURL: URL) async throws -> CloudProject {
        try await createProjectStub?(name, organization, serverURL) ?? .test()
    }
}
