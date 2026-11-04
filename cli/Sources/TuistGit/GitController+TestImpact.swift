import Foundation
import Path

/// The checked-out commit and its parents, which let the server place a commit its history doesn't
/// have yet: a new commit, or a pull request's merge commit, which exists only in the checkout.
public struct GitCheckedOutCommit: Equatable, Sendable {
    public let sha: String
    /// On a pull request's merge commit, the base branch's tip and the pull request's head.
    public let parentSHAs: [String]
    public let isPullRequestMerge: Bool

    public init(sha: String, parentSHAs: [String], isPullRequestMerge: Bool = false) {
        self.sha = sha
        self.parentSHAs = parentSHAs
        self.isPullRequestMerge = isPullRequestMerge
    }
}

/// A file that differs between a baseline and the working tree.
public struct GitChangedFile: Equatable, Sendable {
    /// Relative to the repository's top level.
    public let path: String
    /// `A`, `M`, `D` or `T`, as `git diff --raw` reports it against the baseline.
    public let status: String
    /// The file's blob in the working tree, nil when it's deleted.
    public let blobId: String?

    public init(path: String, status: String, blobId: String?) {
        self.path = path
        self.status = status
        self.blobId = blobId
    }
}

/// The files that differ between a baseline and the working tree, in path order, and whether the
/// working tree had dirty or untracked files, which makes the diff the checkout's alone.
public struct GitChangedFiles: Equatable, Sendable {
    public let files: [GitChangedFile]
    public let dirty: Bool

    public init(files: [GitChangedFile], dirty: Bool) {
        self.files = files
        self.dirty = dirty
    }
}

public enum GitChangedFilesResult: Equatable, Sendable {
    case changed(GitChangedFiles)
    /// The baseline isn't in the checkout and deepening didn't reach it, for the reason given.
    case historyUnavailable(String)
}

extension GitController {
    /// How many commits coverage-based test selection deepens a shallow clone by. It deepens at most
    /// once per invocation, so this is as far back as it looks beyond the checkout.
    public static let testImpactDeepenCommits = 100

    public func deepenShallowClone(workingDirectory: AbsolutePath, refs: [String], limits: GitHistoryLimits) async -> Bool {
        await deepenOnce(git: ["git", "-C", workingDirectory.pathString], refs: refs, limits: limits) == .deepened
    }

    public func ancestorSHAs(workingDirectory: AbsolutePath, limit: Int) async -> [String] {
        guard limit > 0 else { return [] }
        let output = try? await capture(
            arguments: ["git", "-C", workingDirectory.pathString, "rev-list", "--topo-order", "--max-count=\(limit + 1)", "HEAD"]
        )
        return Array((output ?? "").split(whereSeparator: \.isNewline).map(String.init).dropFirst())
    }

    public func checkedOutCommit(workingDirectory: AbsolutePath) async throws -> GitCheckedOutCommit {
        let head = try await currentCommitSHA(workingDirectory: workingDirectory)
        let environment = await ciEnvironment()
        // A depth-1 checkout grafts the parents away; the raw format reads them from the commit object.
        let raw = try? await capture(
            arguments: ["git", "-C", workingDirectory.pathString, "log", "--no-walk", "--no-decorate", "--format=raw", head]
        )
        let parents = raw.map(GitHistoryParser.parseRawParents)?[head] ?? []
        let isPullRequestMerge = parents.count > 1
            && Self.isPullRequestMergeCheckout(ref: Self.ref(environment: environment), head: head, environment: environment)
        return GitCheckedOutCommit(sha: head, parentSHAs: parents, isPullRequestMerge: isPullRequestMerge)
    }

    public func changedFiles(
        workingDirectory: AbsolutePath,
        since baselineSHA: String,
        deepening refs: [String],
        limits: GitHistoryLimits
    ) async throws -> GitChangedFilesResult {
        let git = ["git", "-C", workingDirectory.pathString]
        if await !hasCommit(git: git, sha: baselineSHA),
           let reason = await deepen(git: git, toReach: baselineSHA, refs: refs, limits: limits)
        {
            return .historyUnavailable(reason)
        }

        // `--no-renames` keeps git from reading blobs to pair renames; dirty submodule checkouts
        // aren't changes of this repository.
        let rawDiff = git + ["diff", "--raw", "-z", "--no-renames", "--no-abbrev", "--ignore-submodules=dirty"]
        let committed = GitHistoryParser.parseRawDiff(try await capture(arguments: rawDiff + [baselineSHA, "HEAD"]))
        let workingTree = GitHistoryParser.parseRawDiff(try await capture(arguments: rawDiff + ["HEAD"]))
        let untracked = try await capture(arguments: git + ["ls-files", "--others", "--exclude-standard", "-z"])
            .split(separator: "\0").map(String.init)

        let changes = Self.workingTreeChanges(committed: committed, workingTree: workingTree, untracked: untracked)
        let hashed = try await hashObjects(git: git, paths: changes.filter(\.needsHash).map(\.path))
        return .changed(GitChangedFiles(
            files: Self.changedFiles(committed: committed, workingTreeChanges: changes, hashed: hashed),
            dirty: !workingTree.isEmpty || !untracked.isEmpty
        ))
    }

    private struct WorkingTreeChange {
        let path: String
        let baselineBlob: String?
        let blob: String?
        let needsHash: Bool
        let typeChanged: Bool
    }

    /// A working-tree change is compared with the baseline's blob, so a file the working tree
    /// reverts drops out. The baseline's blob is the committed change's source, or HEAD's when the
    /// commits didn't change the file.
    private static func workingTreeChanges(
        committed: [GitHistoryParser.RawChange],
        workingTree: [GitHistoryParser.RawChange],
        untracked: [String]
    ) -> [WorkingTreeChange] {
        let committedChanges = Dictionary(committed.map { ($0.path, $0) }) { _, last in last }
        func baselineBlob(_ path: String, head: String?) -> String? {
            if let change = committedChanges[path] { return change.srcBlob }
            return head
        }
        let changes = workingTree.map { change in
            WorkingTreeChange(
                path: change.path,
                baselineBlob: baselineBlob(change.path, head: change.srcBlob),
                blob: change.status == "D" ? nil : change.dstBlob,
                needsHash: change.status != "D" && change.dstBlob == nil,
                typeChanged: change.status == "T" || committedChanges[change.path]?.status == "T"
            )
        }
        return changes + untracked.map {
            WorkingTreeChange(path: $0, baselineBlob: baselineBlob($0, head: nil), blob: nil, needsHash: true, typeChanged: false)
        }
    }

    private static func changedFiles(
        committed: [GitHistoryParser.RawChange],
        workingTreeChanges: [WorkingTreeChange],
        hashed: [String: String]
    ) -> [GitChangedFile] {
        var files: [String: GitChangedFile] = [:]
        for change in committed {
            files[change.path] = GitChangedFile(path: change.path, status: change.status, blobId: change.dstBlob)
        }
        for change in workingTreeChanges {
            let blob = change.needsHash ? hashed[change.path] : change.blob
            if blob == change.baselineBlob {
                files[change.path] = nil
                continue
            }
            let status = change.baselineBlob == nil ? "A" : blob == nil ? "D" : change.typeChanged ? "T" : "M"
            files[change.path] = GitChangedFile(path: change.path, status: status, blobId: blob)
        }
        return files.values.sorted { $0.path < $1.path }
    }

    /// Whether the commit is in the checkout. A partial clone would otherwise fetch a missing commit
    /// on its own, and then its trees one by one as the diff reads them, with no budget.
    private func hasCommit(git: [String], sha: String) async -> Bool {
        (try? await capture(arguments: git + ["cat-file", "-e", "\(sha)^{commit}"], environment: ["GIT_NO_LAZY_FETCH": "1"])) !=
            nil
    }

    /// Deepens a shallow clone once through `refs` to reach the commit. Returns why the commit wasn't
    /// reached, nil when it was.
    private func deepen(git: [String], toReach sha: String, refs: [String], limits: GitHistoryLimits) async -> String? {
        let baseline = sha.prefix(12)
        switch await deepenOnce(git: git, refs: refs, limits: limits) {
        case .notShallow:
            return "the baseline \(baseline) is not in the checkout's history"
        case .notAllowed:
            return "shallow clone: the baseline \(baseline) is not in the checkout"
        case .failed:
            return "shallow clone: the baseline \(baseline) is not in the checkout and deepening failed"
        case .timedOut:
            return "shallow clone: the baseline \(baseline) was not reached within \(limits.deepenBudgetSeconds)s"
        case .deepened:
            return await hasCommit(git: git, sha: sha)
                ? nil
                : "shallow clone: the baseline \(baseline) is more than \(Self.testImpactDeepenCommits) commits beyond the checkout"
        }
    }

    private enum DeepenOutcome {
        case deepened, notShallow, notAllowed, failed, timedOut
    }

    /// Fetches `testImpactDeepenCommits` more commits into a shallow clone through `refs`.
    private func deepenOnce(git: [String], refs: [String], limits: GitHistoryLimits) async -> DeepenOutcome {
        let shallow = (try? await capture(arguments: git + ["rev-parse", "--is-shallow-repository"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        guard shallow else { return .notShallow }
        guard limits.remoteAccess == .history, !refs.isEmpty else { return .notAllowed }
        // Blobs are most of what a fetch carries, and the diff reads only trees. Named refs keep
        // the fetch from bringing every branch the checkout's config lists.
        let deadline = Date().addingTimeInterval(TimeInterval(limits.deepenBudgetSeconds))
        let deepen = git + ["fetch", "--no-tags", "--filter=blob:none", "--deepen=\(Self.testImpactDeepenCommits)", "origin"]
            + refs
        switch await fetch(arguments: deepen, deadline: deadline) {
        case .succeeded: return .deepened
        case .failed: return .failed
        case .timedOut: return .timedOut
        }
    }

    /// The blob ids of the working tree's files, batched so a large change set never exceeds the
    /// argument list limit.
    private func hashObjects(git: [String], paths: [String]) async throws -> [String: String] {
        var blobIds: [String: String] = [:]
        for start in stride(from: 0, to: paths.count, by: 500) {
            let batch = Array(paths[start ..< min(start + 500, paths.count)])
            let ids = try await capture(arguments: git + ["hash-object", "--"] + batch).split(whereSeparator: \.isNewline)
            for (path, id) in zip(batch, ids) {
                blobIds[path] = String(id)
            }
        }
        return blobIds
    }
}
