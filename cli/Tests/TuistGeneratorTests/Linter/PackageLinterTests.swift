import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistGenerator
@testable import TuistTesting

final class PackageLinterTests: TuistUnitTestCase {
    var subject: PackageLinter!

    override func setUp() {
        super.setUp()
        subject = PackageLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_when_a_local_path_does_not_exists() async throws {
        let path = try! AbsolutePath(validating: "/NotExists")
        let package = Package.local(path: path)

        let got = try await subject.lint(package)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Package with local path (\(path)) does not exist.", severity: .error)))
    }

    func test_lint_when_a_local_path_exists() async throws {
        let path = try! AbsolutePath(validating: "/")
        let package = Package.local(path: path)

        let got = try await subject.lint(package)

        XCTAssertEmpty(got)
    }

    func test_lint_when_a_remote_url_is__valid() async throws {
        let url = "https://tuist.io"
        let package = Package.remote(url: url, requirement: Requirement.exact(""))

        let got = try await subject.lint(package)

        XCTAssertEmpty(got)
    }
}
