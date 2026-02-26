import Foundation
import Path
import Testing

enum AssertionsTesting {
    static func fixturePath() -> AbsolutePath {
        try! AbsolutePath(
            validating: #filePath
        )
        .parentDirectory
        .parentDirectory
        .parentDirectory
        .appending(components: "Fixtures")
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
