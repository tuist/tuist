import TSCUtility
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class GitControllerTests: TuistUnitTestCase {
    private var subject: GitController!

    override func setUp() {
        super.setUp()
        subject = GitController(system: system)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_cloneInto() throws {
        let url = "https://some/url/to/repo.git"
        let path = try temporaryPath()

        system.succeedCommand(["git", "-C", "\(path.pathString)", "clone", "\(url)"])

        XCTAssertNoThrow(try subject.clone(url: url, into: path))
        XCTAssertTrue(system.called(["git", "-C", path.pathString, "clone", url]))
    }

    func test_cloneTo() throws {
        let url = "https://some/url/to/repo.git"

        system.succeedCommand(["git", "clone", "\(url)"])

        XCTAssertNoThrow(try subject.clone(url: url))
        XCTAssertTrue(system.called(["git", "clone", url]))
    }

    func test_cloneTo_WITH_path() throws {
        let url = "https://some/url/to/repo.git"
        let path = try temporaryPath()

        system.succeedCommand(["git", "clone", "\(url)", path.pathString])

        XCTAssertNoThrow(try subject.clone(url: url, to: path))
        XCTAssertTrue(system.called(["git", "clone", url, path.pathString]))
    }

    func test_checkout() throws {
        let id = "main"

        system.succeedCommand(["git", "checkout", "\(id)"])

        XCTAssertNoThrow(try subject.checkout(id: id, in: nil))
    }

    func test_checkout_WITH_path() throws {
        let id = "main"
        let path = try temporaryPath()

        let expectedCommand = [
            "git",
            "--git-dir",
            path.appending(component: ".git").pathString,
            "--work-tree",
            path.pathString,
            "checkout",
            id,
        ]

        system.succeedCommand(expectedCommand)

        XCTAssertNoThrow(try subject.checkout(id: id, in: path))
        XCTAssertTrue(system.called([
            "git",
            "--git-dir",
            path.appending(component: ".git").pathString,
            "--work-tree",
            path.pathString,
            "checkout",
            id,
        ]))
    }

    func test_parsed_versions() throws {
        let url = "https://some/url/to/repo.git"

        let expectedCommand = [
            "git",
            "ls-remote",
            "-t",
            "--sort=v:refname",
            url,
        ]

        let output = """
            4e4230bb95e1c57e82a1e5f9b4c79486fc2543fb    refs/tags/1.9.0
            There are no versions on this line.
            d265964d42bb934783246c3158297592b4977c3c    refs/tags/1.52.0
            5e17254d4a3c14454ecab6575b4a44d6685d3865    refs/tags/2.0.0
        """

        let expectedResult = [Version(1, 9, 0), Version(1, 52, 0), Version(2, 0, 0)]

        system.succeedCommand(expectedCommand, output: output)

        let result = try subject.remoteTaggedVersions(url: url)

        XCTAssertTrue(system.called(expectedCommand))
        XCTAssertEqual(result, expectedResult)
    }

    func test_currentCommitSHA() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "5e17254d4a3c14454ecab6575b4a44d6685d3865\n"
        )

        // When
        let gitCommitSHA = try subject.currentCommitSHA(workingDirectory: path)

        // Then
        XCTAssertEqual(gitCommitSHA, "5e17254d4a3c14454ecab6575b4a44d6685d3865")
    }

    func test_urlOrigin() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(
            ["git", "-C", path.pathString, "remote", "get-url", "origin"],
            output: "https://github.com/tuist/tuist\n"
        )

        // When
        let urlOrigin = try subject.urlOrigin(workingDirectory: path)

        // Then
        XCTAssertEqual(urlOrigin, "https://github.com/tuist/tuist")
    }

    func test_ref_when_githubRef() throws {
        // When
        let got = subject.ref(
            environment: [
                "GITHUB_REF": "refs/pull/1/merge",
            ]
        )

        // Then
        XCTAssertEqual(got, "refs/pull/1/merge")
    }

    func test_ref_when_codemagicPullRequestNumber() throws {
        // When
        let got = subject.ref(
            environment: [
                "CM_PULL_REQUEST_NUMBER": "2",
            ]
        )

        // Then
        XCTAssertEqual(got, "refs/pull/2/merge")
    }

    func test_ref_when_circle_pull_request() throws {
        // When
        let got = subject.ref(
            environment: [
                "CIRCLE_PULL_REQUEST": "https://github.com/tuist/tuist/pull/6740",
            ]
        )

        // Then
        XCTAssertEqual(got, "refs/pull/6740/merge")
    }

    func test_inGitRepository_when_rev_parse_succeeds() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let isInGitRepository = subject.isInGitRepository(workingDirectory: path)

        // Then
        XCTAssertTrue(isInGitRepository)
    }

    func test_inGitRepository_when_rev_parse_fails() throws {
        // Given
        let path = try temporaryPath()
        system.errorCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let isInGitRepository = subject.isInGitRepository(workingDirectory: path)

        // Then
        XCTAssertFalse(isInGitRepository)
    }

    func test_current_branch_when_main() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(["git", "-C", path.pathString, "branch", "--show-current"], output: "main")

        // When
        let branch = try subject.currentBranch(workingDirectory: path)

        // Then
        XCTAssertEqual(branch, "main")
    }

    func test_current_branch_when_empty() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand(["git", "-C", path.pathString, "branch", "--show-current"], output: "")

        // When
        let branch = try subject.currentBranch(workingDirectory: path)

        // Then
        XCTAssertEqual(branch, nil)
    }
}
