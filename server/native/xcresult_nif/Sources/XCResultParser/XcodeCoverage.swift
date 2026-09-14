import Foundation

/// What only the client knows about the checkout a coverage run was built from, and the result
/// bundle cannot tell whoever processes it: where the checkout lived, the Git blob every tracked
/// source file had, and whether the run left tests out on purpose.
///
/// The client writes it into the result bundle as ``fileName`` before uploading it, or hands it
/// to the parser directly when it processes the bundle itself. A bundle without one is not read
/// for coverage: its paths could not be tied to the repository.
public struct XcodeCoverageManifest: Codable, Equatable, Sendable {
    public static let fileName = "tuist_coverage_manifest.json"

    /// Every absolute spelling of the checkout's root. The compiler records the one the build
    /// used, which is not always the canonical one (`/tmp` and `/private/tmp` on macOS).
    public let rootDirectories: [String]

    /// Whether the run ran a subset of its tests on purpose (selective testing, `-only-testing`,
    /// `-skip-testing`), so files it did not observe may still be covered by the tests it skipped.
    public let partial: Bool

    /// The checkout's tracked source files, relative to the root, with the Git blob of the
    /// contents that were built.
    public let files: [XcodeCoverageSourceFile]

    enum CodingKeys: String, CodingKey {
        case partial, files
        case rootDirectories = "root_directories"
    }

    public init(rootDirectories: [String], partial: Bool, files: [XcodeCoverageSourceFile]) {
        self.rootDirectories = rootDirectories
        self.partial = partial
        self.files = files
    }
}

public struct XcodeCoverageSourceFile: Codable, Equatable, Hashable, Sendable {
    public let path: String
    /// The Git blob object id of the file's contents: what `git hash-object` prints.
    public let gitBlobId: String

    enum CodingKeys: String, CodingKey {
        case path
        case gitBlobId = "git_blob_id"
    }

    public init(path: String, gitBlobId: String) {
        self.path = path
        self.gitBlobId = gitBlobId
    }
}

/// The line coverage a test run observed, read from the result bundle's coverage report and
/// archive and tied to the repository through an ``XcodeCoverageManifest``.
public struct XcodeCoverageReport: Codable, Equatable, Sendable {
    /// Carried over from the manifest.
    public let partial: Bool
    /// One entry per source file the run's instrumented binaries compiled, whichever targets
    /// linked it.
    public let files: [XcodeCoverageFile]
    /// The manifest's files the run did not observe. Only listed for a partial run, where they
    /// are the ones earlier evidence can stand in for.
    public let unobservedFiles: [XcodeCoverageSourceFile]

    enum CodingKeys: String, CodingKey {
        case partial, files
        case unobservedFiles = "unobserved_files"
    }

    public init(partial: Bool, files: [XcodeCoverageFile], unobservedFiles: [XcodeCoverageSourceFile]) {
        self.partial = partial
        self.files = files
        self.unobservedFiles = unobservedFiles
    }
}

public struct XcodeCoverageFile: Codable, Equatable, Sendable {
    /// Relative to the checkout's root when the file lives under it, otherwise the absolute
    /// path the compiler recorded.
    public let path: String
    /// Nil for a file Git does not track: one outside the checkout, generated or ignored.
    public let gitBlobId: String?
    /// The targets whose binaries compiled the file.
    public let targets: [String]
    public let coveredLines: Int
    public let executableLines: Int
    /// The executable lines, ascending, paired with ``executionCounts``.
    public let lineNumbers: [Int]
    public let executionCounts: [Int]
    public let functions: [XcodeCoverageFunction]

    enum CodingKeys: String, CodingKey {
        case path, targets, functions
        case gitBlobId = "git_blob_id"
        case coveredLines = "covered_lines"
        case executableLines = "executable_lines"
        case lineNumbers = "line_numbers"
        case executionCounts = "execution_counts"
    }

    public init(
        path: String,
        gitBlobId: String?,
        targets: [String],
        coveredLines: Int,
        executableLines: Int,
        lineNumbers: [Int],
        executionCounts: [Int],
        functions: [XcodeCoverageFunction]
    ) {
        self.path = path
        self.gitBlobId = gitBlobId
        self.targets = targets
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.lineNumbers = lineNumbers
        self.executionCounts = executionCounts
        self.functions = functions
    }
}

public struct XcodeCoverageFunction: Codable, Equatable, Sendable {
    public let name: String
    public let lineNumber: Int
    public let executionCount: Int
    public let coveredLines: Int
    public let executableLines: Int

    enum CodingKeys: String, CodingKey {
        case name
        case lineNumber = "line_number"
        case executionCount = "execution_count"
        case coveredLines = "covered_lines"
        case executableLines = "executable_lines"
    }

    public init(name: String, lineNumber: Int, executionCount: Int, coveredLines: Int, executableLines: Int) {
        self.name = name
        self.lineNumber = lineNumber
        self.executionCount = executionCount
        self.coveredLines = coveredLines
        self.executableLines = executableLines
    }
}
