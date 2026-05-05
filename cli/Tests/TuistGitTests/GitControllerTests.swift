import FileSystem
import FileSystemTesting
import Testing
import TSCUtility
import TuistEnvironment
import TuistSupport
@testable import TuistGit
@testable import TuistTesting

struct GitControllerTests {
    private let commandRunner = MockCommandRunner()
    private var subject: GitController!

    init() {
        subject = GitController(commandRunner: commandRunner)
    }

    @Test(.inTemporaryDirectory) func topLevelDirectory() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)

        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse", "--show-toplevel"], output: "/path/to/root")

        let gitDirectory = try await subject.topLevelGitDirectory(workingDirectory: path)
        #expect(gitDirectory == "/path/to/root")
        #expect(commandRunner.called(["git", "-C", path.pathString, "rev-parse", "--show-toplevel"]) == true)
    }

    @Test(.inTemporaryDirectory) func cloneInto() async throws {
        let url = "https://some/url/to/repo.git"
        let path = try #require(FileSystem.temporaryTestDirectory)

        commandRunner.succeedCommand(["git", "-C", path.pathString, "clone", url])

        try await subject.clone(url: url, into: path)
        #expect(commandRunner.called(["git", "-C", path.pathString, "clone", url]) == true)
    }

    @Test(.inTemporaryDirectory) func cloneTo() async throws {
        let url = "https://some/url/to/repo.git"

        commandRunner.succeedCommand(["git", "clone", url])

        try await subject.clone(url: url)
        #expect(commandRunner.called(["git", "clone", url]) == true)
    }

    @Test(.inTemporaryDirectory) func cloneTo_WITH_path() async throws {
        let url = "https://some/url/to/repo.git"
        let path = try #require(FileSystem.temporaryTestDirectory)

        commandRunner.succeedCommand(["git", "clone", url, path.pathString])

        try await subject.clone(url: url, to: path)
        #expect(commandRunner.called(["git", "clone", url, path.pathString]) == true)
    }

    @Test(.inTemporaryDirectory) func test_checkout() async throws {
        let id = "main"

        commandRunner.succeedCommand(["git", "checkout", id])

        try await subject.checkout(id: id, in: nil)
    }

    @Test(.inTemporaryDirectory) func checkout_WITH_path() async throws {
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

        commandRunner.succeedCommand(expectedCommand)

        try await subject.checkout(id: id, in: path)
        #expect(commandRunner.called([
            "git",
            "--git-dir",
            path.appending(component: ".git").pathString,
            "--work-tree",
            path.pathString,
            "checkout",
            id,
        ]) == true)
    }

    @Test(.inTemporaryDirectory) func parsed_versions() async throws {
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

        commandRunner.succeedCommand(expectedCommand, output: output)

        let result = try await subject.remoteTaggedVersions(url: url)

        #expect(commandRunner.called(expectedCommand) == true)
        #expect(result == expectedResult)
    }

    @Test(.inTemporaryDirectory) func test_currentCommitSHA() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "5e17254d4a3c14454ecab6575b4a44d6685d3865\n"
        )

        // When
        let gitCommitSHA = try await subject.currentCommitSHA(workingDirectory: path)

        // Then
        #expect(gitCommitSHA == "5e17254d4a3c14454ecab6575b4a44d6685d3865")
    }

    @Test(.inTemporaryDirectory) func test_urlOrigin() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "remote", "get-url", "origin"],
            output: "https://github.com/tuist/tuist\n"
        )

        // When
        let urlOrigin = try await subject.urlOrigin(workingDirectory: path)

        // Then
        #expect(urlOrigin == "https://github.com/tuist/tuist")
    }

    // MARK: - gitInfo() tests

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_github_actions() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_REF": "refs/pull/1/merge",
            "GITHUB_HEAD_REF": "feature-branch",
        ]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "merge-commit-sha\n"
        )
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD^2"],
            output: "actual-pr-head-sha\n"
        )
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "origin")
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "remote", "get-url", "origin"],
            output: "https://github.com/tuist/tuist"
        )

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == "refs/pull/1/merge")
        #expect(gitInfo.branch == "feature-branch")
        #expect(gitInfo.sha == "actual-pr-head-sha")
        #expect(gitInfo.remoteURLOrigin == "https://github.com/tuist/tuist")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_gitlab_ci() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CI_COMMIT_REF_NAME": "develop",
            "CI_EXTERNAL_PULL_REQUEST_IID": "42",
        ]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "def456\n"
        )
        commandRunner.errorCommand(["git", "-C", path.pathString, "rev-parse", "HEAD^2"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == "refs/pull/42/merge")
        #expect(gitInfo.branch == "develop")
        #expect(gitInfo.sha == "def456")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_circleci() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CIRCLE_PULL_REQUEST": "https://github.com/tuist/tuist/pull/6740",
            "CIRCLE_BRANCH": "fix-bug",
        ]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "ghi789\n"
        )
        commandRunner.errorCommand(["git", "-C", path.pathString, "rev-parse", "HEAD^2"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == "refs/pull/6740/merge")
        #expect(gitInfo.branch == "fix-bug")
        #expect(gitInfo.sha == "ghi789")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_buildkite() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "BUILDKITE_BRANCH": "main",
            "BUILDKITE_PULL_REQUEST": "123",
        ]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "jkl012\n"
        )
        commandRunner.errorCommand(["git", "-C", path.pathString, "rev-parse", "HEAD^2"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == "refs/pull/123/merge")
        #expect(gitInfo.branch == "main")
        #expect(gitInfo.sha == "jkl012")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_local_git_repo() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "mno345\n"
        )
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: "local-branch\n"
        )
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == "local-branch")
        #expect(gitInfo.sha == "mno345")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_not_git_repo() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        commandRunner.errorCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == nil)
        #expect(gitInfo.sha == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_no_commits() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.errorCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: "main\n"
        )
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == "main")
        #expect(gitInfo.sha == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_detached_head() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "pqr678\n"
        )
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: ""
        )
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == nil)
        #expect(gitInfo.sha == "pqr678")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_when_azure_devops() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "BUILD_SOURCEBRANCHNAME": "feature/new-feature",
        ]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "stu901\n"
        )
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == "feature/new-feature")
        #expect(gitInfo.sha == "stu901")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_ci_branch_priority_over_git() async throws {
        // Given - CI environment variable should take priority over git command
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_HEAD_REF": "ci-branch",
        ]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "vwx234\n"
        )
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: "local-branch\n"
        )
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "none")

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.ref == nil)
        #expect(gitInfo.branch == "ci-branch") // CI variable takes priority
        #expect(gitInfo.sha == "vwx234")
    }

    @Test(.inTemporaryDirectory) func inGitRepository_when_rev_parse_succeeds() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let isInGitRepository = await subject.isInGitRepository(workingDirectory: path)

        // Then
        #expect(isInGitRepository == true)
    }

    @Test(.inTemporaryDirectory) func inGitRepository_when_rev_parse_fails() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.errorCommand(["git", "-C", path.pathString, "rev-parse"])

        // When
        let isInGitRepository = await subject.isInGitRepository(workingDirectory: path)

        // Then
        #expect(isInGitRepository == false)
    }
}
