import Foundation
import XCTest
@testable import xpmenvkit

final class SettingsTests: XCTestCase {
    func test_equatable() {
        let date = Date()
        let settingsA = Settings(lastTimeUpdatesChecked: date, canaryReference: "ref")
        let settingsB = Settings(lastTimeUpdatesChecked: date, canaryReference: "ref")
        XCTAssertEqual(settingsA, settingsB)
    }
}
