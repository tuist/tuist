import Foundation
import Testing

@testable import TuistSupport

struct StringMD5Tests {
    @Test
    func test_md5() {
        // Given
        let string = "abc"

        // When
        let md5 = string.md5

        // Then
        #expect(md5 == "900150983cd24fb0d6963f7d28e17f72")
    }
}
