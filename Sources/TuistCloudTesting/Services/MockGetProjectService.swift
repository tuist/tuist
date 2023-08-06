import Foundation
import TuistCloud

public final class MockGetProjectService: GetProjectServicing {
    public init() {}

    // swiftlint:disable:next large_tuple
    public var getProjectStub: ((String, String, URL) async throws -> CloudProject)?
    public func getProject(
        accountName: String,
        projectName: String,
        serverURL: URL
    ) async throws -> CloudProject {
        try await getProjectStub?(
            accountName,
            projectName,
            serverURL
        ) ?? .test()
    }
}
