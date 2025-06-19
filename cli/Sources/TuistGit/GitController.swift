import Foundation
import Mockable
import Path
import TSCUtility
import TuistSupport

@Mockable
public protocol GitControlling {
    /// Clones the given `url` **into** the given `path`.
    /// `path` must point to a directory where a git repo can be cloned.
    ///
    /// - Parameters:
    ///   - url: The `url` to the git repository to clone.
    ///   - path: The `AbsolutePath` to clone the git repository.
    func clone(url: String, into path: AbsolutePath) throws

    /// Clones the given `url` **to** the given `path`.
    /// `path` must point to a directory where a git repo can be cloned.
    ///
    /// - Parameters:
    ///   - url: The `url` to the git repository to clone.
    ///   - path: The `AbsolutePath` to clone the git repository.
    func clone(url: String, to path: AbsolutePath?) throws

    /// Checkout to some git `id` in the given `path`.
    ///
    /// The `id` must be something known to the `git checkout` command, which includes:
    ///  - A branch, i.e. `main`.
    ///  - A tag, i.e. `1.0.0`
    ///  - A sha, i.e. `028c13b`
    ///
    /// - Parameters:
    ///   - id: An identifier for the `git checkout` command.
    ///   - path: The path to the git repository (location with `.git` directory) in which to perform the checkout.
    func checkout(id: String, in path: AbsolutePath?) throws

    /// Return the tagged versions of the repository at the given `url`.
    ///
    /// - Parameters:
    ///   - url: The `url` of the git repository.
    func remoteTaggedVersions(url: String) throws -> [Version]

    /// Return the current commit SHA
    func currentCommitSHA(workingDirectory: AbsolutePath) throws -> String

    /// Return the git URL origin
    func urlOrigin(workingDirectory: AbsolutePath) throws -> String

    /// - Returns: `true` if the `git` repository has a remote `origin`.
    func hasUrlOrigin(workingDirectory: AbsolutePath) throws -> Bool

    /// - Returns: `true` if we recognize that we're in a `git` repository
    func isInGitRepository(workingDirectory: AbsolutePath) -> Bool

    /// - Returns: `true` if there are commits in the current branch.
    func hasCurrentBranchCommits(workingDirectory: AbsolutePath) -> Bool

    /// Returns git information including ref, branch, and SHA with CI provider fallbacks.
    /// - Parameter workingDirectory: The working directory of the git repository
    func gitInfo(workingDirectory: AbsolutePath) throws -> GitInfo

    /// Returns the top level `.git` directory path.
    func topLevelGitDirectory(workingDirectory: AbsolutePath) throws -> AbsolutePath
}

/// An implementation of `GitControlling`.
/// Uses the system to execute git commands.
public final class GitController: GitControlling {
    private let system: Systeming
    private let environment: Environmenting

    public init(
        system: Systeming = System.shared,
        environment: Environmenting = Environment.current
    ) {
        self.system = system
        self.environment = environment
    }

    public func topLevelGitDirectory(workingDirectory: AbsolutePath) throws -> AbsolutePath {
        try AbsolutePath(
            validating: try capture(command: "git", "-C", workingDirectory.pathString, "rev-parse", "--show-toplevel")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public func clone(url: String, into path: AbsolutePath) throws {
        try run(command: "git", "-C", path.pathString, "clone", url)
    }

    public func clone(url: String, to path: AbsolutePath? = nil) throws {
        if let path {
            try run(command: "git", "clone", url, path.pathString)
        } else {
            try run(command: "git", "clone", url)
        }
    }

    public func checkout(id: String, in path: AbsolutePath?) throws {
        if let path {
            let gitDirectory = path.appending(component: ".git")
            try run(command: "git", "--git-dir", gitDirectory.pathString, "--work-tree", path.pathString, "checkout", id)
        } else {
            try run(command: "git", "checkout", id)
        }
    }

    public func currentCommitSHA(workingDirectory: AbsolutePath) throws -> String {
        try capture(command: "git", "-C", workingDirectory.pathString, "rev-parse", "HEAD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func hasUrlOrigin(workingDirectory: AbsolutePath) throws -> Bool {
        try capture(command: "git", "-C", workingDirectory.pathString, "remote")
            .components(separatedBy: .newlines)
            .contains("origin")
    }

    public func urlOrigin(workingDirectory: AbsolutePath) throws -> String {
        try capture(command: "git", "-C", workingDirectory.pathString, "remote", "get-url", "origin")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func remoteTaggedVersions(url: String) throws -> [Version] {
        try parseVersions(lsRemote(url: url))
    }

    public func isInGitRepository(workingDirectory: AbsolutePath) -> Bool {
        do {
            try run(command: "git", "-C", workingDirectory.pathString, "rev-parse")
            return true
        } catch {
            return false
        }
    }

    public func hasCurrentBranchCommits(workingDirectory: AbsolutePath) -> Bool {
        do {
            try run(command: "git", "-C", workingDirectory.pathString, "log", "-1")
            return true
        } catch {
            return false
        }
    }

    private static let pullRequestIDEnvironmentVariables = [
        // Codemagic
        "CM_PULL_REQUEST_NUMBER",
        // GitLab
        "CI_EXTERNAL_PULL_REQUEST_IID",
        // Bitrise
        "BITRISE_PULL_REQUEST",
        // AppCircle
        "AC_PULL_NUMBER",
        // Xcode Cloud
        "CI_PULL_REQUEST_NUMBER",
        // Buildkite
        "BUILDKITE_PULL_REQUEST",
        // CircleCI
        "CIRCLE_PR_NUMBER",
    ]

    private static let branchEnvironmentVariables = [
        // GitHub Actions
        "GITHUB_HEAD_REF",
        // GitLab CI
        "CI_COMMIT_REF_NAME",
        // Bitrise
        "BITRISE_GIT_BRANCH",
        // CircleCI
        "CIRCLE_BRANCH",
        // Buildkite
        "BUILDKITE_BRANCH",
        // Codemagic
        "CM_BRANCH",
        // AppCircle
        "AC_GIT_BRANCH",
        // Xcode Cloud
        "CI_BRANCH",
        // TeamCity
        "teamcity.build.branch",
        // Azure DevOps
        "BUILD_SOURCEBRANCHNAME",
    ]

    public func gitInfo(workingDirectory: AbsolutePath) throws -> GitInfo {
        let environment = environment.variables

        // Ref
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

        // Branch
        let ciBranch = Self.branchEnvironmentVariables
            .compactMap { environment[$0] }
            .first { !$0.isEmpty }

        let branchName: String?
        if let ciBranch {
            branchName = ciBranch
        } else if isInGitRepository(workingDirectory: workingDirectory) {
            if let currentBranch = try? capture(command: "git", "-C", workingDirectory.pathString, "branch", "--show-current")
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

        guard isInGitRepository(workingDirectory: workingDirectory)
        else {
            return GitInfo(
                ref: gitRef,
                branch: branchName,
                sha: nil,
                remoteURLOrigin: nil
            )
        }

        // SHA
        let commitSHA: String?
        if hasCurrentBranchCommits(workingDirectory: workingDirectory) {
            commitSHA = try? currentCommitSHA(workingDirectory: workingDirectory)
        } else {
            commitSHA = nil
        }

        let remoteURLOrigin: String?
        if try hasUrlOrigin(workingDirectory: workingDirectory) {
            remoteURLOrigin = try urlOrigin(workingDirectory: workingDirectory)
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

    private func run(command: String...) throws {
        if environment.isVerbose {
            try system.runAndPrint(command, verbose: true, environment: Environment.current.variables)
        } else {
            try system.run(command)
        }
    }

    private func capture(command: String...) throws -> String {
        if environment.isVerbose {
            return try system.capture(command, verbose: true, environment: Environment.current.variables)
        } else {
            return try system.capture(command)
        }
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

    private func lsRemote(url: String) throws -> String {
        try capture(command: "git", "ls-remote", "-t", "--sort=v:refname", url)
    }
}
