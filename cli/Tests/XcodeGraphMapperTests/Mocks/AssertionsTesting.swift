import Foundation
import Path
import Testing
import TuistTestSupport

enum AssertionsTesting {
    static func fixturePath() -> AbsolutePath {
        TestPaths.fixturesDirectory
    }

    /// Resolves a fixture path relative to the project's root.
    static func fixturePath(path: RelativePath) -> AbsolutePath {
        fixturePath().appending(path)
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
