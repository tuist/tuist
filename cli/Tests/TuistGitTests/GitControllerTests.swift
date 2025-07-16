import FileSystem
import FileSystemTesting
import Testing
import TSCUtility
import TuistSupport
@testable import TuistGit
@testable import TuistTesting

struct GitControllerTests {
    private let system = MockSystem()
    private var subject: GitController!

    init() {
        subject = GitController(system: system)
    }

    @Test(.inTemporaryDirectory) func topLevelDirectory() throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand(["git", "-C \(path.pathString)", "rev-parse", "--show-toplevel"], output: "/path/to/root")

        let gitDirectory = try subject.topLevelGitDirectory(workingDirectory: path)
        #expect(gitDirectory == "/path/to/root")
        #expect(system.called(["git", "-C \(path.pathString)", "rev-parse", "--show-toplevel"]) == true)
    }

    @Test(.inTemporaryDirectory) func cloneInto() throws {
        let url = "https://some/url/to/repo.git"
        let path = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand(["git", "-C \(path.pathString)", "clone \(url)"])

        try subject.clone(url: url, into: path)
        #expect(system.called(["git", "-C", path.pathString, "clone", url]) == true)
    }

    @Test(.inTemporaryDirectory) func cloneTo() throws {
        let url = "https://some/url/to/repo.git"

        system.succeedCommand(["git", "clone \(url)"])

        try subject.clone(url: url)
        #expect(system.called(["git", "clone", url]) == true)
    }

    @Test(.inTemporaryDirectory) func cloneTo_WITH_path() throws {
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

    @Test(.inTemporaryDirectory) func checkout_WITH_path() throws {
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

    @Test(.inTemporaryDirectory) func parsed_versions() throws {
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

    // MARK: - gitInfo() tests

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_github_actions() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_REF": "refs/pull/1/merge",
            "GITHUB_HEAD_REF": "feature-branch",
        ]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "abc123\n"
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "origin")
        system.succeedCommand(
            ["git", "-C", path.pathString, "remote", "get-url", "origin"],
            output: "https://github.com/tuist/tuist"
        )

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == "refs/pull/1/merge")
        #expect(gitInfo.branch == "feature-branch")
        #expect(gitInfo.sha == "abc123")
        #expect(gitInfo.remoteURLOrigin == "https://github.com/tuist/tuist")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_gitlab_ci() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CI_COMMIT_REF_NAME": "develop",
            "CI_EXTERNAL_PULL_REQUEST_IID": "42",
        ]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "def456\n"
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == "refs/pull/42/merge")
        #expect(gitInfo.branch == "develop")
        #expect(gitInfo.sha == "def456")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_circleci() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CIRCLE_PULL_REQUEST": "https://github.com/tuist/tuist/pull/6740",
            "CIRCLE_BRANCH": "fix-bug",
        ]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "ghi789\n"
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == "refs/pull/6740/merge")
        #expect(gitInfo.branch == "fix-bug")
        #expect(gitInfo.sha == "ghi789")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_buildkite() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "BUILDKITE_BRANCH": "main",
            "BUILDKITE_PULL_REQUEST": "123",
        ]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "jkl012\n"
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == "refs/pull/123/merge")
        #expect(gitInfo.branch == "main")
        #expect(gitInfo.sha == "jkl012")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_local_git_repo() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "mno345\n"
        )
        system.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: "local-branch\n"
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == "local-branch")
        #expect(gitInfo.sha == "mno345")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_not_git_repo() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        system.errorCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == nil)
        #expect(gitInfo.sha == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_no_commits() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.errorCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: "main\n"
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == "main")
        #expect(gitInfo.sha == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_detached_head() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "pqr678\n"
        )
        system.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: ""
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == nil)
        #expect(gitInfo.sha == "pqr678")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_azure_devops() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "BUILD_SOURCEBRANCHNAME": "feature/new-feature",
        ]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "stu901\n"
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == "feature/new-feature")
        #expect(gitInfo.sha == "stu901")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_ci_branch_priority_over_git() throws {
        // Given - CI environment variable should take priority over git command
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_HEAD_REF": "ci-branch",
        ]
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        system.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        system.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "vwx234\n"
        )
        system.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: "local-branch\n"
        )
        system.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == "ci-branch") // CI variable takes priority
        #expect(gitInfo.sha == "vwx234")
    }

    @Test(.inTemporaryDirectory) func inGitRepository_when_rev_parse_succeeds() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let isInGitRepository = subject.isInGitRepository(workingDirectory: path)

        // Then
        #expect(isInGitRepository == true)
    }

    @Test(.inTemporaryDirectory) func inGitRepository_when_rev_parse_fails() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.errorCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let isInGitRepository = subject.isInGitRepository(workingDirectory: path)

        // Then
        #expect(isInGitRepository == false)
    }
}
