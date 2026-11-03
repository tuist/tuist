import FileSystem
import Foundation
import Path
import TuistServer

/// The tests coverage-based test selection skipped, as xcodebuild receives them: a module none of
/// whose tests was selected is skipped with `-skip-testing:Module`, and single XCTest tests go to the
/// file TestCoverageAttribution reads in the test process, which removes them before they run.
struct TestImpactSkipList: Equatable {
    /// xcodebuild forwards `TEST_RUNNER_`-prefixed variables to the test process without the prefix,
    /// where TestCoverageAttribution reads `TEST_COVERAGE_ATTRIBUTION_SKIP_FILE`.
    static let skipFileEnvironmentVariable = "TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE"

    /// Modules to skip whole.
    let modules: [String]
    /// `module/suite/name` lines for the skip file.
    let tests: [String]

    init(_ skipped: [TestImpactSkippedTest]) {
        var modules: [String] = []
        var tests: [String] = []
        for entry in skipped {
            switch (entry.suite, entry.name) {
            case (nil, nil):
                modules.append(entry.module)
            case let (suite?, name?):
                tests.append("\(entry.module)/\(suite)/\(name)")
            default:
                // The server never collapses tests into a suite, and the skip file can't express one.
                continue
            }
        }
        self.init(modules: modules, tests: tests)
    }

    /// Reads the list back from `identifiers`, as a build persists it for the test phase.
    init(identifiers: [String]) {
        let components = identifiers.map { $0.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false) }
        self.init(
            modules: components.filter { $0.count == 1 }.map { String($0[0]) },
            tests: zip(identifiers, components).filter { $0.1.count == 3 }.map(\.0)
        )
    }

    init(modules: [String], tests: [String]) {
        self.modules = Array(Set(modules)).sorted()
        self.tests = Array(Set(tests)).sorted()
    }

    var isEmpty: Bool { modules.isEmpty && tests.isEmpty }

    /// The list as `RunMetadata` persists it: bare module names and `module/suite/name` lines.
    var identifiers: [String] { modules + tests }

    /// Writes the skip file into `directory` when there are single tests to skip, and returns the
    /// environment that points the test process at it.
    func environment(directory: AbsolutePath, fileSystem: FileSysteming) async throws -> [String: String] {
        guard !tests.isEmpty else { return [:] }
        let path = directory.appending(component: "test-impact-skip.txt")
        try await fileSystem.writeText(tests.joined(separator: "\n") + "\n", at: path, encoding: .utf8, options: [.overwrite])
        return [Self.skipFileEnvironmentVariable: path.pathString]
    }
}
