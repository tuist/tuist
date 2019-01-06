import Basic
import Foundation
import XCTest

public extension XCTestCase {
    /// Returns the absolute path to a fixture in the Tests/Fixtures directory.
    ///
    /// - Parameter path: Path relative to the fixtures directory.
    /// - Returns: Absolute path to the fixture.
    func fixture(path: RelativePath) -> AbsolutePath {
        return AbsolutePath(#file)
            .parentDirectory // Extensions
            .parentDirectory // TuistCoreTesting
            .parentDirectory // Sources
            .parentDirectory // Tuist
            .appending(RelativePath("Tests/Fixtures"))
            .appending(path)
    }
}
