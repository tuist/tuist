import Foundation
@testable import xpmenvkit

final class MockGitHubClient: GitHubClienting {
    var executeCallCount: UInt = 0
    var executeStub: ((URLRequest) throws -> Any)?

    func execute(request: URLRequest) throws -> Any {
        executeCallCount += 1
        return try executeStub?(request) ?? [:]
    }
}
