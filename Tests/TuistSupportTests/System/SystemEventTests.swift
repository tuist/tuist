import Foundation
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class SystemEventTests: TuistUnitTestCase {
    func test_mapToString_when_standardOutput() {
        // Given
        let value = "test"
        let data = value.data(using: .utf8)!
        let subject = SystemEvent<Data>.standardOutput(data)

        // When
        let got = subject.mapToString()

        // Then
    }
}
