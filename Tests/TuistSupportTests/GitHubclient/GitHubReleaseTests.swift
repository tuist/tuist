import Foundation
import TSCBasic
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class GitHubReleaseTests: TuistUnitTestCase {
    func test_latest_returns_the_right_request() {
        // Given
        let subject = GitHubRelease.latest(repositoryFullName: "tuist/tuist")

        // Then
        XCTAssertHTTPMethod(subject, "GET")
        XCTAssertURLPath(subject, path: "/repos/tuist/tuist/releases/latest")
    }

    func test_release_returns_the_right_request() {
        // Given
        let subject = GitHubRelease.release(repositoryFullName: "tuist/tuist", version: "1.2.3")

        // Then
        XCTAssertHTTPMethod(subject, "GET")
        XCTAssertURLPath(subject, path: "/repos/tuist/tuist/releases/tags/1.2.3")
    }

    func test_releases() {
        // Given
        let subject = GitHubRelease.releases(repositoryFullName: "tuist/tuist")

        // Then
        XCTAssertHTTPMethod(subject, "GET")
        XCTAssertURLPath(subject, path: "/repos/tuist/tuist/releases")
    }
}
