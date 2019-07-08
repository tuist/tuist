import Foundation
import XCTest
@testable import tuistenv

final class GitHubRequestsFactoryTests: XCTestCase {
    var subject: GitHubRequestsFactory!
    var baseURL: URL!

    override func setUp() {
        super.setUp()
        baseURL = URL(string: "http://test.com")
        subject = GitHubRequestsFactory(baseURL: baseURL)
    }

    func test_releasesRepository() {
        XCTAssertEqual(GitHubRequestsFactory.repository, "tuist/tuist")
    }

    func test_releases() {
        let got = subject.releases()
        XCTAssertEqual(got.httpMethod, "GET")
        XCTAssertEqual(got.url, baseURL.appendingPathComponent("/repos/\(GitHubRequestsFactory.repository)/releases"))
        XCTAssertNil(got.httpBody)
    }

    func test_release() {
        let got = subject.release(tag: "1.2.3")
        XCTAssertEqual(got.httpMethod, "GET")
        XCTAssertEqual(got.url, baseURL.appendingPathComponent("/repos/\(GitHubRequestsFactory.repository)/releases/tags/1.2.3"))
        XCTAssertNil(got.httpBody)
    }

    func test_getContent() {
        let got = subject.getContent(ref: "master", path: "path/to/file")
        XCTAssertEqual(got.httpMethod, "GET")
        let components = URLComponents(url: got.url!, resolvingAgainstBaseURL: true)!
        XCTAssertEqual(components.query, "ref=master")
        XCTAssertEqual(components.path, "/repos/\(GitHubRequestsFactory.repository)/contents/path/to/file")
    }
}
