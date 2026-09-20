import Foundation

/// Which files each test of a run executed: the evidence test selection plans over ("a test is a
/// candidate when a file it covered changed") and what says how much of the suite has evidence.
///
/// The client's coverage observer records, per test, the coverage counters that moved; the client
/// reduces them to source files and writes the result into the result bundle as ``fileName``,
/// with the paths as the compiler recorded them. Whoever parses the bundle ties them to the
/// repository with the run's ``XcodeCoverageManifest`` (``inRepository(manifest:)``), so the
/// local-mode payload and the server's processor report the same evidence.
public struct TestCoverageEvidence: Codable, Equatable, Sendable {
    public static let fileName = "tuist_test_coverage_evidence.json"

    public enum Kind: String, Codable, Sendable {
        /// What one test executed, between its start and its end.
        case test
        /// What ran around a suite's tests and belongs to none: class `setUp`, a one-time
        /// bootstrap. Every test of the suite may depend on it.
        case suite
        /// Everything the target's process executed: the floor for each of its tests.
        case target
    }

    public struct Scope: Codable, Equatable, Sendable {
        public var kind: Kind
        public var module: String
        /// Empty for a target scope and for a test outside any suite.
        public var suite: String
        /// Empty unless the scope is a test.
        public var name: String
        /// Indices into ``TestCoverageEvidence/paths``, ascending.
        public var files: [Int]

        public init(kind: Kind, module: String, suite: String, name: String, files: [Int]) {
            self.kind = kind
            self.module = module
            self.suite = suite
            self.name = name
            self.files = files
        }
    }

    /// Every file some scope covered, once; scopes refer to them by index.
    public var paths: [String]
    public var scopes: [Scope]
    /// Tests the observer saw that overlapped another test of their process (Swift Testing
    /// running in parallel), so nothing could be attributed to them.
    public var unattributedTests: Int

    enum CodingKeys: String, CodingKey {
        case paths, scopes
        case unattributedTests = "unattributed_tests"
    }

    public init(paths: [String], scopes: [Scope], unattributedTests: Int = 0) {
        self.paths = paths
        self.scopes = scopes
        self.unattributedTests = unattributedTests
    }

    /// The evidence over repository-relative paths, without the files Git cannot vouch for
    /// (outside the checkout, or in a dependency checkout) and without the scopes left with
    /// nothing.
    public func inRepository(manifest: XcodeCoverageManifest) -> TestCoverageEvidence {
        let roots = XcodeCoverageParser.roots(manifest.rootDirectories)
        var keptPaths: [String] = []
        var indexByPath: [String: Int] = [:]
        var newIndex: [Int?] = Array(repeating: nil, count: paths.count)
        for (index, path) in paths.enumerated() {
            let relative = XcodeCoverageParser.relativize(path, to: roots)
            guard !relative.hasPrefix("/"), !XcodeCoverageParser.isDependencyPath(relative) else { continue }
            if let existing = indexByPath[relative] {
                newIndex[index] = existing
            } else {
                indexByPath[relative] = keptPaths.count
                newIndex[index] = keptPaths.count
                keptPaths.append(relative)
            }
        }
        let keptScopes = scopes.compactMap { scope -> Scope? in
            var scope = scope
            scope.files = Array(Set(scope.files.compactMap { $0 < newIndex.count ? newIndex[$0] : nil })).sorted()
            return scope.files.isEmpty ? nil : scope
        }
        return TestCoverageEvidence(paths: keptPaths, scopes: keptScopes, unattributedTests: unattributedTests)
    }

    /// The evidence a client wrote into the bundle, or nil when it did not.
    public static func read(fromResultBundle path: URL) -> TestCoverageEvidence? {
        let file = path.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(TestCoverageEvidence.self, from: data)
    }

    public func write(toResultBundle path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: path.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

extension TestSummary {
    /// The summary with the run's evidence attached; evidence with no scope left is dropped.
    public func applying(coverageEvidence evidence: TestCoverageEvidence?) -> TestSummary {
        guard let evidence, !evidence.scopes.isEmpty else { return self }
        var summary = self
        summary.coverageEvidence = evidence
        return summary
    }
}
