import Foundation
import XCTest

@testable import TuistSupport

final class StringMD5Tests: XCTestCase {
    func test_md5() {
        // Given
        let string = "abc"

        // When
        let md5 = string.md5

        // Then
        XCTAssertEqual(md5, "900150983cd24fb0d6963f7d28e17f72")
    }
}
