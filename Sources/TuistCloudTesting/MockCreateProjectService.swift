import Foundation
import TuistCloud

public final class MockCreateProjectService: CreateProjectServicing {
    public init() {}

    // swiftlint:disable:next large_tuple
    public var createProjectStub: ((String, String?, URL) async throws -> String)?
    public func createProject(name: String, organizationName: String?, serverURL: URL) async throws -> String {
        try await createProjectStub?(name, organizationName, serverURL) ?? ""
    }
}
