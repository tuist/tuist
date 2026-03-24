import Path
import Testing
import TuistTesting

@testable import TuistRootDirectoryLocator

struct RootDirectoryLocatorErrorTests {
    @Test
    func type_when_rootDirectoryNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/")
        let error = RootDirectoryLocatorError.rootDirectoryNotFound(path)

        // Then
        #expect(error.type == .abort)
    }

    @Test
    func description_when_rootDirectoryNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/")
        let error = RootDirectoryLocatorError.rootDirectoryNotFound(path)

        // Then
        #expect(error
            .description ==
            "Couldn't locate the root directory from path \(path.pathString). The root directory is the closest directory that contains a Tuist or a .git directory.")
    }
}
