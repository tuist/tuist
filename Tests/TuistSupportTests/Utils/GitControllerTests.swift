import FileSystem
import FileSystemTesting
import Testing
import TSCUtility
@testable import TuistSupport
@testable import TuistSupportTesting

struct GitControllerTests {
    private let system = MockSystem()
    private var subject: GitController!

    init() {
        subject = GitController(system: system)
    }

    @Test(.inTemporaryDirectory) func test_cloneInto() throws {
        let url = "https://some/url/to/repo.git"
        let path = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand(["git", "-C \(path.pathString)", "clone \(url)"])

        try subject.clone(url: url, into: path)
        #expect(system.called(["git", "-C", path.pathString, "clone", url]) == true)
    }

    @Test(.inTemporaryDirectory) func test_cloneTo() throws {
        let url = "https://some/url/to/repo.git"

        system.succeedCommand(["git", "clone \(url)"])

        try subject.clone(url: url)
        #expect(system.called(["git", "clone", url]) == true)
    }

    @Test(.inTemporaryDirectory) func test_cloneTo_WITH_path() throws {
        let url = "https://some/url/to/repo.git"
        let path = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand(["git", "clone \(url)", path.pathString])

        try subject.clone(url: url, to: path)
        #expect(system.called(["git", "clone", url, path.pathString]) == true)
    }

    @Test(.inTemporaryDirectory) func test_checkout() throws {
        let id = "main"

        system.succeedCommand(["git", "checkout \(id)"])

        try subject.checkout(id: id, in: nil)
    }

    @Test(.inTemporaryDirectory) func test_checkout_WITH_path() throws {
        let id = "main"
        let path = try #require(FileSystem.temporaryTestDirectory)

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

        try subject.checkout(id: id, in: path)
        #expect(system.called([
            "git",
            "--git-dir",
            path.appending(component: ".git").pathString,
            "--work-tree",
            path.pathString,
            "checkout",
            id,
        ]) == true)
    }

    @Test(.inTemporaryDirectory) func test_parsed_versions() throws {
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

        #expect(system.called(expectedCommand) == true)
        #expect(result == expectedResult)
    }

    @Test(.inTemporaryDirectory) func test_currentCommitSHA() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "5e17254d4a3c14454ecab6575b4a44d6685d3865\n"
        )

        // When
        let gitCommitSHA = try subject.currentCommitSHA(workingDirectory: path)

        // Then
        #expect(gitCommitSHA == "5e17254d4a3c14454ecab6575b4a44d6685d3865")
    }

    @Test(.inTemporaryDirectory) func test_urlOrigin() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(
            ["git", "-C", path.pathString, "remote", "get-url", "origin"],
            output: "https://github.com/tuist/tuist\n"
        )

        // When
        let urlOrigin = try subject.urlOrigin(workingDirectory: path)

        // Then
        #expect(urlOrigin == "https://github.com/tuist/tuist")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func test_ref_when_githubRef() throws {
        // When
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_REF": "refs/pull/1/merge",
        ]
        let got = subject.ref()

        // Then
        #expect(got == "refs/pull/1/merge")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func test_ref_when_codemagicPullRequestNumber() throws {
        // When
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CM_PULL_REQUEST_NUMBER": "2",
        ]
        let got = subject.ref()

        // Then
        #expect(got == "refs/pull/2/merge")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func test_ref_when_circle_pull_request() throws {
        // When
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CIRCLE_PULL_REQUEST": "https://github.com/tuist/tuist/pull/6740",
        ]
        let got = subject.ref()

        // Then
        #expect(got == "refs/pull/6740/merge")
    }

    @Test(.inTemporaryDirectory) func test_inGitRepository_when_rev_parse_succeeds() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let isInGitRepository = subject.isInGitRepository(workingDirectory: path)

        // Then
        #expect(isInGitRepository == true)
    }

    @Test(.inTemporaryDirectory) func test_inGitRepository_when_rev_parse_fails() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.errorCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let isInGitRepository = subject.isInGitRepository(workingDirectory: path)

        // Then
        #expect(isInGitRepository == false)
    }

    @Test(.inTemporaryDirectory) func test_current_branch_when_main() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(["git", "-C", path.pathString, "branch", "--show-current"], output: "main")

        // When
        let branch = try subject.currentBranch(workingDirectory: path)

        // Then
        #expect(branch == "main")
    }

    @Test(.inTemporaryDirectory) func test_current_branch_when_empty() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(["git", "-C", path.pathString, "branch", "--show-current"], output: "")

        // When
        let branch = try subject.currentBranch(workingDirectory: path)

        // Then
        #expect(branch == nil)
    }
}
