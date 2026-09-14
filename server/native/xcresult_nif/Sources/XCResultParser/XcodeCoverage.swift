import Foundation

/// Aggregate line coverage for one test run, as `xccov view --report --json`
/// describes it: every target the scheme gathered coverage for, and each
/// source file that target compiled with its covered and executable line
/// counts.
///
/// A source file linked into several targets (a framework's file and the
/// test bundle that links the framework statically, say) appears under each
/// of them with identical counts, exactly as `xccov` reports it. Consumers
/// that want a per-repository figure dedupe by path.
public struct XcodeCoverageReport: Codable, Equatable, Sendable {
    public let targets: [XcodeCoverageTarget]

    public init(targets: [XcodeCoverageTarget]) {
        self.targets = targets
    }
}

public struct XcodeCoverageTarget: Codable, Equatable, Sendable {
    public let name: String
    public let coveredLines: Int
    public let executableLines: Int
    public let files: [XcodeCoverageFile]

    enum CodingKeys: String, CodingKey {
        case name, files
        case coveredLines = "covered_lines"
        case executableLines = "executable_lines"
    }

    public init(name: String, coveredLines: Int, executableLines: Int, files: [XcodeCoverageFile]) {
        self.name = name
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.files = files
    }
}

public struct XcodeCoverageFile: Codable, Equatable, Sendable {
    /// Relative to the root directory the report was parsed against when the
    /// file lives under it, otherwise the absolute path `xccov` reported.
    public let path: String
    public let coveredLines: Int
    public let executableLines: Int

    enum CodingKeys: String, CodingKey {
        case path
        case coveredLines = "covered_lines"
        case executableLines = "executable_lines"
    }

    public init(path: String, coveredLines: Int, executableLines: Int) {
        self.path = path
        self.coveredLines = coveredLines
        self.executableLines = executableLines
    }
}
