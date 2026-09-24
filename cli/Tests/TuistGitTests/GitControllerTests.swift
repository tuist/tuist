import FileSystem
import FileSystemTesting
import Foundation
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

    @Test(.inTemporaryDirectory) func sourceFileBlobIds() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let git = ["git", "-C", path.pathString]

        commandRunner.succeedCommand(
            git + ["ls-files", "--stage", "-z"],
            output: [
                "100644 aaa 0\tSources/A.swift",
                "100644 bbb 0\tSources/B.swift",
                "100644 ccc 0\tREADME.md",
                "160000 ddd 0\tVendor/Submodule.swift",
            ].joined(separator: "\0") + "\0"
        )
        commandRunner.succeedCommand(git + ["diff", "--name-only", "--diff-filter=d", "-z"], output: "Sources/B.swift\0")
        commandRunner.succeedCommand(
            git + ["ls-files", "--others", "--exclude-standard", "-z"],
            output: "Sources/New.m\0notes.txt\0"
        )
        commandRunner.succeedCommand(
            git + ["hash-object", "--", "Sources/B.swift", "Sources/New.m"],
            output: "b2\nnew\n"
        )

        let got = try await subject.sourceFileBlobIds(workingDirectory: path, pathExtensions: ["swift", "m"])

        // The working tree's contents win over the index's for a changed file.
        #expect(got == ["Sources/A.swift": "aaa", "Sources/B.swift": "b2", "Sources/New.m": "new"])
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

    @Test func isGitAvailable_when_git_exists() async {
        // Given
        commandRunner.whichStub = { name in
            #expect(name == "git")
            return "/usr/bin/git"
        }

        // When
        let isGitAvailable = await subject.isGitAvailable()

        // Then
        #expect(isGitAvailable == true)
    }

    @Test func isGitAvailable_when_git_does_not_exist() async {
        // Given
        commandRunner.whichStub = { name in
            #expect(name == "git")
            return nil
        }

        // When
        let isGitAvailable = await subject.isGitAvailable()

        // Then
        #expect(isGitAvailable == false)
    }

    @Test(.inTemporaryDirectory) func test_currentTag() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "describe", "--tags", "--exact-match"],
            output: "1.2.3\n"
        )

        // When
        let tag = try await subject.currentTag(workingDirectory: path)

        // Then
        #expect(tag == "1.2.3")
    }

    @Test(.inTemporaryDirectory) func currentTag_when_head_does_not_point_to_a_tag() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.errorCommand(["git", "-C", path.pathString, "describe", "--tags", "--exact-match"])

        // When
        let tag = try await subject.currentTag(workingDirectory: path)

        // Then
        #expect(tag == nil)
    }

    @Test(.inTemporaryDirectory) func hasUncommittedChanges_when_status_has_output() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "status", "--porcelain"],
            output: " M Package.swift\n"
        )

        // When
        let hasUncommittedChanges = try await subject.hasUncommittedChanges(workingDirectory: path)

        // Then
        #expect(hasUncommittedChanges == true)
    }

    @Test(.inTemporaryDirectory) func hasUncommittedChanges_when_status_is_empty() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "status", "--porcelain"],
            output: "\n"
        )

        // When
        let hasUncommittedChanges = try await subject.hasUncommittedChanges(workingDirectory: path)

        // Then
        #expect(hasUncommittedChanges == false)
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

    /// `GITHUB_HEAD_REF` is a pull-request variable, so a push falls through to
    /// git, and a workflow that checks out an explicit SHA is detached, where git
    /// cannot name the branch either. CI on the default branch is where most of a
    /// project's cache comes from, so reporting no branch there is the whole
    /// point of the branch being reported at all.
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func gitInfo_when_github_actions_pushes_to_a_branch_with_a_detached_head() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_REF_NAME": "main",
            "GITHUB_REF_TYPE": "branch",
        ]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "some-sha\n"
        )
        // Detached: git reports no current branch.
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: "\n"
        )
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "origin")
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "remote", "get-url", "origin"],
            output: "https://github.com/tuist/tuist"
        )

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.branch == "main")
    }

    /// A tag push sets `GITHUB_REF_NAME` to the tag. Reporting it as the branch
    /// would attribute the build to a ref no branch ever matches.
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func gitInfo_when_github_actions_pushes_a_tag() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_REF": "refs/tags/4.1.0",
            "GITHUB_REF_NAME": "4.1.0",
            "GITHUB_REF_TYPE": "tag",
        ]
        commandRunner.succeedCommand(["git", "-C", path.pathString, "rev-parse"])
        commandRunner.succeedCommand(["git", "-C", path.pathString, "log", "-1"])
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "rev-parse", "HEAD"],
            output: "some-sha\n"
        )
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "branch", "--show-current"],
            output: "\n"
        )
        commandRunner.succeedCommand(["git", "-C", path.pathString, "remote"], output: "origin")
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "remote", "get-url", "origin"],
            output: "https://github.com/tuist/tuist"
        )

        // When
        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        // Then
        #expect(gitInfo.branch == nil, "a tag is not a branch")
    }

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

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_reads_the_base_branch_and_pull_request_number()
        async throws
    {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_REF": "refs/pull/17/merge",
            "GITHUB_HEAD_REF": "feature",
            "GITHUB_BASE_REF": "main",
        ]
        commandRunner.errorCommand(["git", "-C", path.pathString, "rev-parse"])

        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        #expect(gitInfo.baseBranch == "main")
        #expect(gitInfo.pullRequestNumber == 17)
        #expect(GitController.pullRequestNumber(ref: nil, environment: ["CI_MERGE_REQUEST_IID": "9"]) == 9)
        #expect(GitController.pullRequestNumber(ref: "refs/heads/main", environment: [:]) == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func gitInfo_strips_a_full_base_ref() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = ["SYSTEM_PULLREQUEST_TARGETBRANCH": "refs/heads/develop"]
        commandRunner.errorCommand(["git", "-C", path.pathString, "rev-parse"])

        let gitInfo = try await subject.gitInfo(workingDirectory: path)

        #expect(gitInfo.baseBranch == "develop")
        #expect(gitInfo.pullRequestNumber == nil)
    }

    @Test func parseCommits_reads_sha_parents_and_time() {
        let commits = GitHistoryParser.parseCommits("head mid 1700000000\nmid base other 1600000000\nroot 1500000000\nbad\n")

        #expect(commits.map(\.sha) == ["head", "mid", "root"])
        #expect(commits.map(\.parents) == [["mid"], ["base", "other"], []])
        #expect(commits[0].committedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func parseChangedFiles_joins_the_raw_listing_with_the_hunks() {
        let raw = [
            ":100644 100644 aaa bbb M", "Sources/A.swift",
            ":000000 100644 0000000 ccc A", "Sources/New.swift",
            ":100644 000000 ddd 0000000 D", "Sources/Gone.swift",
            ":100644 100644 eee fff R090", "Sources/Old.swift", "Sources/Renamed.swift",
        ].joined(separator: "\0") + "\0"
        let unified = """
        diff --git a/Sources/A.swift b/Sources/A.swift
        --- a/Sources/A.swift
        +++ b/Sources/A.swift
        @@ -3,2 +3,4 @@
        +x
        @@ -10 +12 @@
        +y
        @@ -20,2 +22,0 @@
        -gone
        diff --git a/Sources/New.swift b/Sources/New.swift
        --- /dev/null
        +++ b/Sources/New.swift
        @@ -0,0 +1,2 @@
        +a
        +b
        diff --git a/Sources/Gone.swift b/Sources/Gone.swift
        --- a/Sources/Gone.swift
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -a
        """

        let (files, dropped) = GitHistoryParser.parseChangedFiles(
            raw: raw, unified: unified, limits: GitHistoryLimits(maxChangedFiles: 3, maxHunksPerFile: 1)
        )

        #expect(dropped == 1)
        #expect(files.map(\.path) == ["Sources/A.swift", "Sources/New.swift", "Sources/Gone.swift"])
        #expect(files[0] == GitChangedFile(
            path: "Sources/A.swift", previousPath: nil, status: .modified, blobId: "bbb",
            hunks: [GitHunk(start: 3, end: 6)], truncated: true
        ))
        #expect(files[1].status == .added)
        #expect(files[1].hunks == [GitHunk(start: 1, end: 2)])
        #expect(files[2] == GitChangedFile(
            path: "Sources/Gone.swift", previousPath: nil, status: .deleted, blobId: nil, hunks: [], truncated: false
        ))
    }

    @Test(.inTemporaryDirectory) func gitHistory_collects_the_merge_base_commits_and_changed_files() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let git = ["git", "-C", path.pathString]
        commandRunner.succeedCommand(git + ["rev-parse", "--show-object-format"], output: "sha1\n")
        commandRunner.succeedCommand(git + ["rev-parse", "--is-shallow-repository"], output: "false\n")
        commandRunner.succeedCommand(git + ["rev-parse", "--verify", "--quiet", "origin/main^{commit}"], output: "basehead\n")
        commandRunner.succeedCommand(git + ["merge-base", "origin/main", "head"], output: "base\n")
        commandRunner.succeedCommand(
            git + ["log", "--format=%H %P %ct", "--max-count=10", "--since=30.days.ago", "head"],
            output: "head base 1700000100\nbase 1700000000\n"
        )
        commandRunner.succeedCommand(
            git + ["diff", "--raw", "--no-abbrev", "-z", "-M", "base", "head"],
            output: ":100644 100644 aaa bbb M\0Sources/A.swift\0"
        )
        commandRunner.succeedCommand(
            git + ["diff", "-U0", "-M", "--no-color", "--no-ext-diff", "base", "head"],
            output: "+++ b/Sources/A.swift\n@@ -1 +1,2 @@\n+a\n+b\n"
        )

        let history = try await subject.gitHistory(
            workingDirectory: path,
            headSHA: "head",
            baseBranch: "main",
            limits: GitHistoryLimits(windowDays: 30, windowCommits: 10)
        )

        #expect(history.objectFormat == "sha1")
        #expect(history.headSHA == "head")
        #expect(history.mergeBaseSHA == "base")
        #expect(history.commits.map(\.sha) == ["head", "base"])
        #expect(history.changedFiles.map(\.path) == ["Sources/A.swift"])
        #expect(history.changedFiles[0].hunks == [GitHunk(start: 1, end: 2)])
        #expect(history.fallbackReason == nil)
    }

    @Test(.inTemporaryDirectory) func gitHistory_stops_deepening_at_the_history_window() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let git = ["git", "-C", path.pathString]
        commandRunner.succeedCommand(git + ["rev-parse", "--show-object-format"], output: "sha1\n")
        commandRunner.succeedCommand(git + ["rev-parse", "--is-shallow-repository"], output: "true\n")
        commandRunner.succeedCommand(git + ["rev-parse", "--verify", "--quiet", "origin/main^{commit}"], output: "basehead\n")
        // Never resolves, so deepening runs until a bound stops it.
        commandRunner.errorCommand(git + ["merge-base", "origin/main", "head"])
        commandRunner.succeedCommand(git + ["fetch", "--no-tags", "--deepen=50", "origin"])
        commandRunner.succeedCommand(
            git + ["log", "--format=%H %P %ct", "--max-count=10", "--since=30.days.ago", "head"],
            output: "head 1700000100\n"
        )

        let history = try await subject.gitHistory(
            workingDirectory: path,
            headSHA: "head",
            baseBranch: "main",
            limits: GitHistoryLimits(windowDays: 30, windowCommits: 10, deepenBudgetSeconds: 5)
        )

        #expect(history.mergeBaseSHA == nil)
        #expect(commandRunner.called(git + ["fetch", "--no-tags", "--deepen=50", "origin"]))
        #expect(!commandRunner.called(git + ["fetch", "--no-tags", "--deepen=100", "origin"]))
    }

    @Test(.inTemporaryDirectory) func gitHistory_stops_deepening_when_a_fetch_fails() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let git = ["git", "-C", path.pathString]
        commandRunner.succeedCommand(git + ["rev-parse", "--show-object-format"], output: "sha1\n")
        commandRunner.succeedCommand(git + ["rev-parse", "--is-shallow-repository"], output: "true\n")
        commandRunner.succeedCommand(git + ["rev-parse", "--verify", "--quiet", "origin/main^{commit}"], output: "basehead\n")
        commandRunner.errorCommand(git + ["merge-base", "origin/main", "head"])
        // The deepen fetch fails, as it does offline. Retrying it until the
        // budget expires would overflow the depth long before that.
        commandRunner.errorCommand(git + ["fetch", "--no-tags", "--deepen=50", "origin"])
        commandRunner.succeedCommand(
            git + ["log", "--format=%H %P %ct", "--max-count=5000", "--since=365.days.ago", "head"],
            output: "head 1700000100\n"
        )

        let history = try await subject.gitHistory(
            workingDirectory: path, headSHA: "head", baseBranch: "main", limits: GitHistoryLimits()
        )

        #expect(history.mergeBaseSHA == nil)
        #expect(!commandRunner.called(git + ["fetch", "--no-tags", "--deepen=100", "origin"]))
    }

    @Test(.inTemporaryDirectory) func gitHistory_explains_a_missing_base_branch() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let git = ["git", "-C", path.pathString]
        commandRunner.succeedCommand(git + ["rev-parse", "--show-object-format"], output: "sha256\n")
        commandRunner.succeedCommand(
            git + ["log", "--format=%H %P %ct", "--max-count=5000", "--since=365.days.ago", "head"],
            output: "head 1700000100\n"
        )

        let history = try await subject.gitHistory(
            workingDirectory: path, headSHA: "head", baseBranch: nil, limits: GitHistoryLimits()
        )

        #expect(history.objectFormat == "sha256")
        #expect(history.mergeBaseSHA == nil)
        #expect(history.changedFiles.isEmpty)
        #expect(history.fallbackReason == "no base branch is known")
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

    @Test(.inTemporaryDirectory) func commitFiles_lists_the_index_with_blobs_and_modes_up_to_the_limit() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand(
            ["git", "-C", path.pathString, "ls-files", "--stage", "-z"],
            output: "100644 aaa 0\tPackage.resolved\0100755 bbb 0\tScripts/run.sh\0100644 ccc 1\tTuist/Conflict.swift\0160000 ddd 0\tVendor/Submodule\0100644 eee 0\tTuist/Package.swift\0"
        )

        let listing = try await subject.commitFiles(workingDirectory: path, limit: 2)

        #expect(listing.files == [
            GitCommitFile(path: "Package.resolved", blobId: "aaa", mode: 0o100644),
            GitCommitFile(path: "Scripts/run.sh", blobId: "bbb", mode: 0o100755),
        ])
        #expect(listing.truncated)

        let whole = try await subject.commitFiles(workingDirectory: path, limit: 10)
        #expect(whole.files.map(\.path) == ["Package.resolved", "Scripts/run.sh", "Tuist/Package.swift"])
        #expect(!whole.truncated)
    }
}
