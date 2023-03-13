import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

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

    func test_lint_when_a_local_path_does_not_exists() {
        let path = try! AbsolutePath(validating: "/NotExists")
        let package = Package.local(path: path)

        let got = subject.lint(package)

        XCTContainsLintingIssue(got, LintingIssue(reason: "Package with local path (\(path)) does not exist.", severity: .error))
    }

    func test_lint_when_a_remote_url_is_not_valid() {
        let url = "\\NotValidUrl"
        let package = Package.remote(url: url, requirement: Requirement.exact(""))

        let got = subject.lint(package)

        XCTContainsLintingIssue(
            got,
            LintingIssue(reason: "Package with remote URL (\(url)) does not have a valid URL.", severity: .error)
        )
    }

    func test_lint_when_a_local_path_exists() {
        let path = try! AbsolutePath(validating: "/")
        let package = Package.local(path: path)

        let got = subject.lint(package)

        XCTAssertEmpty(got)
    }

    func test_lint_when_a_remote_url_is__valid() {
        let url = "https://tuist.io"
        let package = Package.remote(url: url, requirement: Requirement.exact(""))

        let got = subject.lint(package)

        XCTAssertEmpty(got)
    }
}
