import Feature
import SwiftTestingSupport
import Testing
import TestSupport
import XCTest

final class AppTests: XCTestCase {
    func testFeatureMessageWithXCTestSupport() {
        TestSupport.assertMessage(Feature().message)
    }
}

@Suite struct AppSwiftTestingTests {
    @Test func featureMessageMatchesFixture() {
        #expect(Feature().message == TestSupport.expectedMessage)
    }

    @Test func featureMessageMatchesSwiftTestingSupportFixture() {
        SwiftTestingSupport.expectMessage(Feature().message)
    }
}
