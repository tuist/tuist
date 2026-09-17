import Foundation

/// A commit as the server's commit graph stores it: its parents, first parent first, and the
/// committer date.
public struct GitHistoryCommit: Equatable, Sendable {
    public let sha: String
    public let parents: [String]
    public let committedAt: Date

    public init(sha: String, parents: [String], committedAt: Date) {
        self.sha = sha
        self.parents = parents
        self.committedAt = committedAt
    }
}

/// An inclusive range of changed lines in a file at the head of a diff.
public struct GitHunk: Equatable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// A file changed between the merge base and the head.
public struct GitChangedFile: Equatable, Sendable {
    public enum Status: String, Sendable {
        case added, modified, deleted, renamed
    }

    /// The path at the head, relative to the repository root.
    public let path: String
    /// The path before a rename.
    public let previousPath: String?
    public let status: Status
    /// The file's blob at the head; nil for a deleted file.
    public let blobId: String?
    public let hunks: [GitHunk]
    /// Whether the hunks stop short because the file's diff exceeded the limits.
    public let truncated: Bool

    public init(path: String, previousPath: String?, status: Status, blobId: String?, hunks: [GitHunk], truncated: Bool) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.blobId = blobId
        self.hunks = hunks
        self.truncated = truncated
    }
}

/// A file the project tracks beyond the sources its tests compile (a dependency manifest, generator
/// configuration, a fixture, a snapshot), with the blob it has at the run's commit.
public struct GitTrackedFile: Equatable, Sendable {
    public let path: String
    public let blobId: String

    public init(path: String, blobId: String) {
        self.path = path
        self.blobId = blobId
    }
}

/// The tracked files a run saw, and whether the listing stopped at the limit.
public struct GitTrackedFiles: Equatable, Sendable {
    public let files: [GitTrackedFile]
    public let truncated: Bool

    public init(files: [GitTrackedFile], truncated: Bool) {
        self.files = files
        self.truncated = truncated
    }
}

/// How much history the client collects for a run. The server tells the client its values
/// (`GET .../tests/git-history/settings`); these are the defaults when it cannot.
public struct GitHistoryLimits: Equatable, Sendable {
    /// How many days back the commit slice reaches.
    public var windowDays: Int
    /// How many commits back the commit slice reaches.
    public var windowCommits: Int
    /// How long deepening a shallow clone may take before giving up on the merge base.
    public var deepenBudgetSeconds: Int
    /// Commits per upload request.
    public var uploadBatchSize: Int
    /// Changed files listed with hunks; the rest are dropped and the run says so.
    public var maxChangedFiles: Int
    /// Hunks kept per changed file; a file with more is marked truncated.
    public var maxHunksPerFile: Int
    /// Git pathspec globs, relative to the repository root, of the files snapshotted with each run.
    public var trackedFileGlobs: [String]
    /// Tracked files listed; beyond it the snapshot is marked truncated.
    public var trackedFileLimit: Int

    public init(
        windowDays: Int = 365,
        windowCommits: Int = 5000,
        deepenBudgetSeconds: Int = 60,
        uploadBatchSize: Int = 500,
        maxChangedFiles: Int = 2000,
        maxHunksPerFile: Int = 200,
        trackedFileGlobs: [String] = [],
        trackedFileLimit: Int = 5000
    ) {
        self.windowDays = windowDays
        self.windowCommits = windowCommits
        self.deepenBudgetSeconds = deepenBudgetSeconds
        self.uploadBatchSize = uploadBatchSize
        self.maxChangedFiles = maxChangedFiles
        self.maxHunksPerFile = maxHunksPerFile
        self.trackedFileGlobs = trackedFileGlobs
        self.trackedFileLimit = trackedFileLimit
    }
}

/// What a checkout can tell about a run's place in the repository's history. Anything the
/// checkout could not resolve is nil, with `fallbackReason` saying why, and the server may
/// complete it from the VCS provider.
public struct GitHistory: Equatable, Sendable {
    /// `sha1` or `sha256`.
    public let objectFormat: String
    public let headSHA: String
    public let baseBranch: String?
    public let mergeBaseSHA: String?
    /// The commits reachable from the head within the limits, newest first.
    public let commits: [GitHistoryCommit]
    /// The files changed between the merge base and the head; empty without a merge base.
    public let changedFiles: [GitChangedFile]
    public let fallbackReason: String?

    public init(
        objectFormat: String,
        headSHA: String,
        baseBranch: String?,
        mergeBaseSHA: String?,
        commits: [GitHistoryCommit],
        changedFiles: [GitChangedFile],
        fallbackReason: String?
    ) {
        self.objectFormat = objectFormat
        self.headSHA = headSHA
        self.baseBranch = baseBranch
        self.mergeBaseSHA = mergeBaseSHA
        self.commits = commits
        self.changedFiles = changedFiles
        self.fallbackReason = fallbackReason
    }
}
