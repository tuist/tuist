import Path
import TuistSupportTesting
import XCTest

@testable import TuistCore

final class RootDirectoryLocatorErrorTests: TuistUnitTestCase {
    func test_type_when_rootDirectoryNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/")
        let error = RootDirectoryLocatorError.rootDirectoryNotFound(path)

        // Then
        XCTAssertEqual(error.type, .abort)
    }

    func test_description_when_rootDirectoryNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/")
        let error = RootDirectoryLocatorError.rootDirectoryNotFound(path)

        // Then
        XCTAssertEqual(
            error.description,
            "Couldn't locate the root directory from path \(path.pathString). The root directory is the closest directory that contains a Tuist or a .git directory."
        )
    }
}
