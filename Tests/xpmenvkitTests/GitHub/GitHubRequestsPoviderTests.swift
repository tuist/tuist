import Foundation
import XCTest
@testable import xpmenvkit

final class GitHubRequestsProviderTests: XCTestCase {
    var subject: GitHubRequestsProvider!
    var baseURL: URL!

    override func setUp() {
        super.setUp()
        baseURL = URL(string: "http://test.com")
        subject = GitHubRequestsProvider(baseURL: baseURL)
    }

    func test_releasesRepository() {
        XCTAssertEqual(GitHubRequestsProvider.releasesRepository, "xcode-project-manager/releases")
    }

    func test_releases() {
        let got = subject.releases()
        XCTAssertEqual(got.httpMethod, "GET")
        XCTAssertEqual(got.url, baseURL.appendingPathComponent("/repos/\(GitHubRequestsProvider.releasesRepository)/releases"))
        XCTAssertNil(got.httpBody)
    }
}
