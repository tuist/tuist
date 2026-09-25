import Foundation
import Mockable
import Path
import TSCUtility
import TuistEnvironment
import TuistProcess
import TuistSupport

@Mockable
public protocol GitControlling {
    /// Clones the given `url` **into** the given `path`.
    /// `path` must point to a directory where a git repo can be cloned.
    ///
    /// - Parameters:
    ///   - url: The `url` to the git repository to clone.
    ///   - path: The `AbsolutePath` to clone the git repository.
    func clone(url: String, into path: AbsolutePath) async throws

    /// Clones the given `url` **to** the given `path`.
    /// `path` must point to a directory where a git repo can be cloned.
    ///
    /// - Parameters:
    ///   - url: The `url` to the git repository to clone.
    ///   - path: The `AbsolutePath` to clone the git repository.
    func clone(url: String, to path: AbsolutePath?) async throws

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
    func checkout(id: String, in path: AbsolutePath?) async throws

    /// Return the tagged versions of the repository at the given `url`.
    ///
    /// - Parameters:
    ///   - url: The `url` of the git repository.
    func remoteTaggedVersions(url: String) async throws -> [Version]

    /// Return the current commit SHA
    func currentCommitSHA(workingDirectory: AbsolutePath) async throws -> String

    /// Return whether git is available in the current environment.
    func isGitAvailable() async -> Bool

    /// Return the current tag if HEAD points exactly to one.
    func currentTag(workingDirectory: AbsolutePath) async throws -> String?

    /// Return whether the git working tree has uncommitted changes.
    func hasUncommittedChanges(workingDirectory: AbsolutePath) async throws -> Bool

    /// Return the git URL origin
    func urlOrigin(workingDirectory: AbsolutePath) async throws -> String

    /// - Returns: `true` if the `git` repository has a remote `origin`.
    func hasUrlOrigin(workingDirectory: AbsolutePath) async throws -> Bool

    /// - Returns: `true` if we recognize that we're in a `git` repository
    func isInGitRepository(workingDirectory: AbsolutePath) async -> Bool

    /// - Returns: `true` if there are commits in the current branch.
    func hasCurrentBranchCommits(workingDirectory: AbsolutePath) async -> Bool

    /// Returns git information including ref, branch, and SHA with CI provider fallbacks.
    /// - Parameter workingDirectory: The working directory of the git repository
    func gitInfo(workingDirectory: AbsolutePath) async throws -> GitInfo

    /// Returns the top level `.git` directory path.
    func topLevelGitDirectory(workingDirectory: AbsolutePath) async throws -> AbsolutePath

    /// What the checkout can tell about `headSHA`'s place in the repository's history: the merge
    /// base with `baseBranch`, the commits reachable from the head within `limits`, and the files
    /// changed since the merge base with their hunks. A shallow clone is deepened within the budget
    /// to find the merge base. Nothing here throws for a missing piece: it comes back nil with a
    /// reason, and the server may complete it from the VCS provider.
    /// - Parameters:
    ///   - workingDirectory: The repository's top level.
    ///   - headSHA: The commit the run is for; HEAD when nil.
    ///   - baseBranch: The branch the commit will merge into.
    ///   - limits: How much to collect.
    func gitHistory(
        workingDirectory: AbsolutePath,
        headSHA: String?,
        baseBranch: String?,
        limits: GitHistoryLimits
    ) async throws -> GitHistory

    /// Every file of the commit's tree with the blob it has, at most `limit` of them in path order,
    /// which is what the server keys the listing by.
    func commitFiles(workingDirectory: AbsolutePath, sha: String, limit: Int) async throws -> GitCommitFiles

    /// The Git blob object id of every source file with one of `pathExtensions`, keyed by its path
    /// relative to `workingDirectory`, which must be the repository's top level. Tracked files the
    /// working tree has changed, and untracked files Git does not ignore, are hashed from the
    /// working tree, so each id describes the contents a build would compile.
    func sourceFileBlobIds(workingDirectory: AbsolutePath, pathExtensions: Set<String>) async throws -> [String: String]
}

/// An implementation of `GitControlling`.
/// Uses CommandRunner to execute git commands.
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

    public func sourceFileBlobIds(workingDirectory: AbsolutePath, pathExtensions: Set<String>) async throws -> [String: String] {
        let git = ["git", "-C", workingDirectory.pathString]
        let isSource: (String) -> Bool = { pathExtensions.contains((($0 as NSString).pathExtension).lowercased()) }
        var blobIds: [String: String] = [:]

        // `<mode> <object> <stage>\t<path>`, NUL-terminated so no path is quoted.
        for entry in try await capture(arguments: git + ["ls-files", "--stage", "-z"]).split(separator: "\0") {
            guard let tab = entry.firstIndex(of: "\t") else { continue }
            let path = String(entry[entry.index(after: tab)...])
            let fields = entry[..<tab].split(separator: " ")
            // A submodule's entry names a commit, not a blob.
            guard isSource(path), fields.count >= 2, fields[0] != "160000" else { continue }
            blobIds[path] = String(fields[1])
        }

        let modified = try await capture(arguments: git + ["diff", "--name-only", "--diff-filter=d", "-z"])
        let untracked = try await capture(arguments: git + ["ls-files", "--others", "--exclude-standard", "-z"])
        let workingTreePaths = Array(Set((modified + "\0" + untracked).split(separator: "\0").map(String.init).filter(isSource)))
            .sorted()

        // Batched so a large change set never exceeds the argument list limit.
        for start in stride(from: 0, to: workingTreePaths.count, by: 500) {
            let batch = Array(workingTreePaths[start ..< min(start + 500, workingTreePaths.count)])
            let ids = try await capture(arguments: git + ["hash-object", "--"] + batch)
                .split(whereSeparator: \.isNewline)
            for (path, id) in zip(batch, ids) {
                blobIds[path] = String(id)
            }
        }

        return blobIds
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
            try await run(command: "git", "--git-dir", gitDirectory.pathString, "--work-tree", path.pathString, "checkout", id)
        } else {
            try await run(command: "git", "checkout", id)
        }
    }

    public func currentCommitSHA(workingDirectory: AbsolutePath) async throws -> String {
        try await capture(command: "git", "-C", workingDirectory.pathString, "rev-parse", "HEAD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func isGitAvailable() async -> Bool {
        await commandRunner.commandExists("git")
    }

    public func currentTag(workingDirectory: AbsolutePath) async throws -> String? {
        let tag = try? await capture(command: "git", "-C", workingDirectory.pathString, "describe", "--tags", "--exact-match")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tag, !tag.isEmpty else { return nil }
        return tag
    }

    public func hasUncommittedChanges(workingDirectory: AbsolutePath) async throws -> Bool {
        let status = try await capture(command: "git", "-C", workingDirectory.pathString, "status", "--porcelain")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !status.isEmpty
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
        try parseVersions(try await lsRemote(url: url))
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

    private static let baseBranchEnvironmentVariables = [
        // GitHub Actions
        "GITHUB_BASE_REF",
        // GitLab CI
        "CI_MERGE_REQUEST_TARGET_BRANCH_NAME",
        "CI_EXTERNAL_PULL_REQUEST_TARGET_BRANCH_NAME",
        // Bitrise
        "BITRISEIO_GIT_BRANCH_DEST",
        // Buildkite
        "BUILDKITE_PULL_REQUEST_BASE_BRANCH",
        // Codemagic
        "CM_PULL_REQUEST_DEST",
        // Xcode Cloud
        "CI_PULL_REQUEST_TARGET_BRANCH",
        // Azure DevOps (a full ref, refs/heads/main)
        "SYSTEM_PULLREQUEST_TARGETBRANCH",
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

    /// GitHub's branch, for the events `GITHUB_HEAD_REF` does not cover.
    ///
    /// That variable is defined for pull requests and nothing else, so a push, or
    /// a workflow that checks out an explicit SHA, falls through to git. A
    /// detached checkout leaves git unable to name the branch either, and the
    /// build then reports no branch at all.
    ///
    /// `GITHUB_REF_NAME` is set on every event, but on a tag push it names the
    /// tag, and a tag is not a branch: recording one would attribute the build to
    /// a ref no trunk can ever match. `GITHUB_REF_TYPE` is what separates them.
    private static func githubBranch(environment: [String: String]) -> String? {
        guard environment["GITHUB_REF_TYPE"] == "branch",
              let name = environment["GITHUB_REF_NAME"],
              !name.isEmpty
        else { return nil }
        return name
    }

    public func gitInfo(workingDirectory: AbsolutePath) async throws -> GitInfo {
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

        // The base branch and pull request number, from the CI provider only: a checkout does not
        // know what its commit will merge into.
        let baseBranch = Self.baseBranchEnvironmentVariables
            .compactMap { environment[$0] }
            .first { !$0.isEmpty }
            .map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : $0 }
        let pullRequestNumber = Self.pullRequestNumber(ref: gitRef, environment: environment)

        // Branch
        let ciBranch = Self.branchEnvironmentVariables
            .compactMap { environment[$0] }
            .first { !$0.isEmpty }
            ?? Self.githubBranch(environment: environment)

        let branchName: String?
        if let ciBranch {
            branchName = ciBranch
        } else if await isInGitRepository(workingDirectory: workingDirectory) {
            if let currentBranch = try? await capture(
                command: "git",
                "-C",
                workingDirectory.pathString,
                "branch",
                "--show-current"
            )
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !currentBranch.isEmpty {
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
                remoteURLOrigin: nil,
                baseBranch: baseBranch,
                pullRequestNumber: pullRequestNumber
            )
        }

        // SHA — if CI checked out a PR merge ref (e.g. refs/pull/N/merge),
        // HEAD is an ephemeral merge commit. Use the second parent (the actual
        // PR branch tip) instead, since the merge commit doesn't exist on the remote.
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
            remoteURLOrigin: remoteURLOrigin,
            baseBranch: baseBranch,
            pullRequestNumber: pullRequestNumber
        )
    }

    /// The pull request number from a `refs/pull/<n>/...` ref (which the CI variables above are
    /// folded into), or GitLab's merge request id.
    static func pullRequestNumber(ref: String?, environment: [String: String]) -> Int? {
        if let ref, let match = ref.wholeMatch(of: #/refs/(?:pull|merge-requests)/(\d+)/.*/#) {
            return Int(match.1)
        }
        return ["CI_MERGE_REQUEST_IID"].compactMap { environment[$0] }.compactMap(Int.init).first
    }

    private func run(command: String...) async throws {
        if environment.isVerbose {
            try await commandRunner.runAndPrint(arguments: command, environment: hardenedEnvironment())
        } else {
            try await commandRunner.runAndWait(arguments: command, environment: hardenedEnvironment())
        }
    }

    private func capture(command: String...) async throws -> String {
        try await capture(arguments: command)
    }

    func capture(arguments: [String]) async throws -> String {
        try await commandRunner.capture(arguments: arguments, environment: hardenedEnvironment())
    }

    /// Environment overrides that keep every spawned `git` invocation
    /// non-interactive on CI runners. The subprocess inherits `tuist`'s
    /// stdin, so anything that opens a credential prompt, spawns
    /// `gpg` for signature verification, or otherwise reads from stdin
    /// blocks indefinitely with no output. The runner then cancels the
    /// step at its wall-clock timeout and the user is left with a silent
    /// multi-hour hang.
    ///
    /// `GIT_TERMINAL_PROMPT=0` disables the terminal prompt path.
    /// `GIT_ASKPASS=/usr/bin/false` forces any askpass helper to fail
    /// immediately (`/usr/bin/false` exists on both macOS and Linux, while
    /// `/bin/false` is not guaranteed on macOS and would print a spurious
    /// `fatal: cannot exec` line into stderr before the disabled-prompt
    /// path took over). `GIT_CONFIG_COUNT=1` plus the `KEY_0`/`VALUE_0`
    /// pair overrides `log.showSignature` for the lifetime of the
    /// subprocess, which keeps `git log` from invoking `gpg`
    /// regardless of the repository's configuration.
    private static let hardenedEnvironmentOverrides: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_ASKPASS": "/usr/bin/false",
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "log.showSignature",
        "GIT_CONFIG_VALUE_0": "false",
    ]

    private func hardenedEnvironment() -> [String: String] {
        Environment.current.variables.merging(Self.hardenedEnvironmentOverrides) { _, new in new }
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
