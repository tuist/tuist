import Foundation
import TuistCloud

public final class MockCreateProjectService: CreateProjectServicing {
    public init() {}
    
    public var createProjectStub: ((String, String, URL) async throws -> Void)?
    public func createProject(name: String, organizationName: String, serverURL: URL) async throws {
        try await createProjectStub?(name, organizationName, serverURL)
    }
}
