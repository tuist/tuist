import Foundation
import TSCBasic
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class StringExtrasTests: TuistUnitTestCase {
    func test_camelized() {
        // Given
        let subject = "Framework-iOSResources"

        // When
        let got = subject.camelized

        // Then
        XCTAssertEqual(got, "frameworkIOSResources")
    }
}
