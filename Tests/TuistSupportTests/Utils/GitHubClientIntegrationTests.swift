import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class GitHubClientIntegrationTests: TuistTestCase {
    
    func test_something() throws {
        let expectation = XCTestExpectation(description: "GitHubClient deferred when token")
        var release: GitHubRelease?
        let client = GitHubClient()
        _ = client.deferred(resource: GitHubRelease.latest(repositoryFullName: "tuist/tuist"))
            .sink { error in
                print(error)
                expectation.fulfill()
            } receiveValue: { (response) in
                print(response)
                release = response.object
            }
        wait(for: [expectation], timeout: 10.0)


    }
}
