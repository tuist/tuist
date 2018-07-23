import Foundation
@testable import TuistEnvKit
import XCTest

final class GitHubRequestsFactoryTests: XCTestCase {
    var subject: GitHubRequestsFactory!
    var baseURL: URL!

    override func setUp() {
        super.setUp()
        baseURL = URL(string: "http://test.com")
        subject = GitHubRequestsFactory(baseURL: baseURL)
    }

    func test_releasesRepository() {
        XCTAssertEqual(GitHubRequestsFactory.releasesRepository, "tuist/tuist")
    }

    func test_releases() {
        let got = subject.releases()
        XCTAssertEqual(got.httpMethod, "GET")
        XCTAssertEqual(got.url, baseURL.appendingPathComponent("/repos/\(GitHubRequestsFactory.releasesRepository)/releases"))
        XCTAssertNil(got.httpBody)
    }
}
