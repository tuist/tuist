import Foundation
import Path
import Testing
import TuistTestSupport

enum AssertionsTesting {
    // MARK: - Fixtures

    /// Resolves a fixture path relative to the project's root.
    static func fixturePath(path: RelativePath) -> AbsolutePath {
        TestPaths.fixturesDirectory.appending(path)
    }
}

extension AbsolutePath: Swift.ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        do {
            self = try AbsolutePath(validating: value)
        } catch {
            Issue.record("Invalid path at: \(value) - Error: \(error)")
            self = AbsolutePath("/")
        }
    }
}
