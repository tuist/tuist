import Foundation
import TSCBasic
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class InvalidGlobTests: TuistUnitTestCase {
    func test_description() {
        // Given
        let subject = InvalidGlob(pattern: "/path/**/*", nonExistentPath: AbsolutePath("/path"))

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The directory \"/path\" defined in the glob pattern \"/path/**/*\" does not exist.")
    }
}
