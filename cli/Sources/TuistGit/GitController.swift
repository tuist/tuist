import Command
import Foundation
import Mockable
import Path
import TSCUtility
import TuistEnvironment
import TuistSupport

@Mockable
public protocol GitControlling {
    func clone(url: String, into path: AbsolutePath) async throws
    func clone(url: String, to path: AbsolutePath?) async throws
    func checkout(id: String, in path: AbsolutePath?) async throws
    func remoteTaggedVersions(url: String) async throws -> [Version]
    func currentCommitSHA(workingDirectory: AbsolutePath) async throws -> String
    func urlOrigin(workingDirectory: AbsolutePath) async throws -> String
    func hasUrlOrigin(workingDirectory: AbsolutePath) async throws -> Bool
    func isInGitRepository(workingDirectory: AbsolutePath) async -> Bool
    func hasCurrentBranchCommits(workingDirectory: AbsolutePath) async -> Bool
    func gitInfo(workingDirectory: AbsolutePath) async throws -> GitInfo
    func topLevelGitDirectory(workingDirectory: AbsolutePath) async throws -> AbsolutePath
}

public struct GitController: GitControlling {
    private let commandRunner: CommandRunning
    private let environment: Environmenting

    public init(
        commandRunner: CommandRunning = CommandRunner(),
        environment: Environmenting = Environment.current
    ) {
        self.commandRunner = commandRunner
        self.environment = environment
    }

    public func topLevelGitDirectory(workingDirectory: AbsolutePath) async throws -> AbsolutePath {
        try AbsolutePath(
            validating: try await capture(command: "git", "-C", workingDirectory.pathString, "rev-parse", "--show-toplevel")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public func clone(url: String, into path: AbsolutePath) async throws {
        try await run(command: "git", "-C", path.pathString, "clone", url)
    }

    public func clone(url: String, to path: AbsolutePath? = nil) async throws {
        if let path {
            try await run(command: "git", "clone", url, path.pathString)
        } else {
            try await run(command: "git", "clone", url)
        }
    }

    public func checkout(id: String, in path: AbsolutePath?) async throws {
        if let path {
            let gitDirectory = path.appending(component: ".git")
            try await run(
                command: "git", "--git-dir", gitDirectory.pathString, "--work-tree", path.pathString, "checkout", id
            )
        } else {
            try await run(command: "git", "checkout", id)
        }
    }

    public func currentCommitSHA(workingDirectory: AbsolutePath) async throws -> String {
        try await capture(command: "git", "-C", workingDirectory.pathString, "rev-parse", "HEAD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func hasUrlOrigin(workingDirectory: AbsolutePath) async throws -> Bool {
        try await capture(command: "git", "-C", workingDirectory.pathString, "remote")
            .components(separatedBy: .newlines)
            .contains("origin")
    }

    public func urlOrigin(workingDirectory: AbsolutePath) async throws -> String {
        try await capture(command: "git", "-C", workingDirectory.pathString, "remote", "get-url", "origin")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func remoteTaggedVersions(url: String) async throws -> [Version] {
        try await parseVersions(lsRemote(url: url))
    }

    public func isInGitRepository(workingDirectory: AbsolutePath) async -> Bool {
        do {
            try await run(command: "git", "-C", workingDirectory.pathString, "rev-parse")
            return true
        } catch {
            return false
        }
    }

    public func hasCurrentBranchCommits(workingDirectory: AbsolutePath) async -> Bool {
        do {
            try await run(command: "git", "-C", workingDirectory.pathString, "log", "-1")
            return true
        } catch {
            return false
        }
    }

    private static let pullRequestIDEnvironmentVariables = [
        "CM_PULL_REQUEST_NUMBER",
        "CI_EXTERNAL_PULL_REQUEST_IID",
        "BITRISE_PULL_REQUEST",
        "AC_PULL_NUMBER",
        "CI_PULL_REQUEST_NUMBER",
        "BUILDKITE_PULL_REQUEST",
        "CIRCLE_PR_NUMBER",
    ]

    private static let branchEnvironmentVariables = [
        "GITHUB_HEAD_REF",
        "CI_COMMIT_REF_NAME",
        "BITRISE_GIT_BRANCH",
        "CIRCLE_BRANCH",
        "BUILDKITE_BRANCH",
        "CM_BRANCH",
        "AC_GIT_BRANCH",
        "CI_BRANCH",
        "teamcity.build.branch",
        "BUILD_SOURCEBRANCHNAME",
    ]

    public func gitInfo(workingDirectory: AbsolutePath) async throws -> GitInfo {
        let environment = environment.variables

        let gitRef: String?
        if let githubRef = environment["GITHUB_REF"] {
            gitRef = githubRef
        } else if let circleCIRef = environment["CIRCLE_PULL_REQUEST"] {
            if let url = URL(string: circleCIRef),
               let pullRequestID = url.pathComponents.last
            {
                gitRef = "refs/pull/\(pullRequestID)/merge"
            } else {
                gitRef = nil
            }
        } else if let pullRequestID = Self.pullRequestIDEnvironmentVariables
            .compactMap({ environment[$0] })
            .first(where: { !$0.isEmpty })
        {
            gitRef = "refs/pull/\(pullRequestID)/merge"
        } else {
            gitRef = nil
        }

        let ciBranch = Self.branchEnvironmentVariables
            .compactMap { environment[$0] }
            .first { !$0.isEmpty }

        let branchName: String?
        if let ciBranch {
            branchName = ciBranch
        } else if await isInGitRepository(workingDirectory: workingDirectory) {
            if let currentBranch = try? await capture(
                command: "git", "-C", workingDirectory.pathString, "branch", "--show-current"
            )
            .trimmingCharacters(in: .whitespacesAndNewlines),
                !currentBranch.isEmpty
            {
                branchName = currentBranch
            } else {
                branchName = nil
            }
        } else {
            branchName = nil
        }

        guard await isInGitRepository(workingDirectory: workingDirectory)
        else {
            return GitInfo(
                ref: gitRef,
                branch: branchName,
                sha: nil,
                remoteURLOrigin: nil
            )
        }

        let commitSHA: String?
        if await hasCurrentBranchCommits(workingDirectory: workingDirectory) {
            let isPullRequestMergeRef = gitRef?.hasPrefix("refs/pull/") == true
            if isPullRequestMergeRef,
               let secondParent = try? await capture(
                   command: "git", "-C", workingDirectory.pathString, "rev-parse", "HEAD^2"
               ).trimmingCharacters(in: .whitespacesAndNewlines),
               !secondParent.isEmpty
            {
                commitSHA = secondParent
            } else {
                commitSHA = try? await currentCommitSHA(workingDirectory: workingDirectory)
            }
        } else {
            commitSHA = nil
        }

        let remoteURLOrigin: String?
        if try await hasUrlOrigin(workingDirectory: workingDirectory) {
            remoteURLOrigin = try await urlOrigin(workingDirectory: workingDirectory)
        } else {
            remoteURLOrigin = nil
        }

        return GitInfo(
            ref: gitRef,
            branch: branchName,
            sha: commitSHA,
            remoteURLOrigin: remoteURLOrigin
        )
    }

    private func run(command: String...) async throws {
        if environment.isVerbose {
            try await commandRunner.run(arguments: command).pipedStream().awaitCompletion()
        } else {
            try await commandRunner.run(arguments: command).awaitCompletion()
        }
    }

    private func capture(command: String...) async throws -> String {
        try await commandRunner.run(arguments: command).concatenatedString()
    }

    private func parseVersions(_ unparsed: String) throws -> [Version] {
        let regex = try NSRegularExpression(pattern: ##"tags/([0-9]+.[0-9]+.[0-9]+)"##, options: [])
        let changelogRange = NSRange(
            unparsed.startIndex ..< unparsed.endIndex,
            in: unparsed
        )
        let matches = regex.matches(in: unparsed, options: [], range: changelogRange)

        let versions = matches.map { result -> Version in
            let matchRange = result.range(at: 1)
            return Version(stringLiteral: String(unparsed[Range(matchRange, in: unparsed)!]))
        }
        return versions
    }

    private func lsRemote(url: String) async throws -> String {
        try await capture(command: "git", "ls-remote", "-t", "--sort=v:refname", url)
    }
}
