import Combine
import CombineExt
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

class GitEnvironmentIntegrationTests: TuistTestCase {
    var subject: GitEnvironment!

    override func setUp() {
        super.setUp()
        subject = GitEnvironment()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_it_works() {
        // Given
        let expectation = XCTestExpectation(description: "git.environment.integrationtest")
        var githubCredentials: [GithubCredentials?] = []
        let publisher = subject.githubCredentials()
        var cancellables: Set<AnyCancellable> = Set()

        // When
        let cancellable = publisher.sink { _ in
            expectation.fulfill()
        } receiveValue: { credentials in
            githubCredentials.append(credentials)
        }
        cancellables.insert(cancellable)
        wait(for: [expectation], timeout: 10.0)

        // Then
        XCTAssertEqual(githubCredentials.count, 1)
        XCTAssertNotNil(githubCredentials.first ?? nil)
    }
}
