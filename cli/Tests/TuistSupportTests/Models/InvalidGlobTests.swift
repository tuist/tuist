import Foundation
import Path
import Testing
@testable import TuistSupport
@testable import TuistTesting

struct InvalidGlobTests {
    @Test
    func test_description() throws {
        // Given
        let subject = InvalidGlob(pattern: "/path/**/*", nonExistentPath: try AbsolutePath(validating: "/path"))

        // When
        let got = subject.description

        // Then
        #expect(got == "The directory \"/path\" defined in the glob pattern \"/path/**/*\" does not exist.")
    }
}
