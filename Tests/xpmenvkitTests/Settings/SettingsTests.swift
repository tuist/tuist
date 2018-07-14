import Foundation
import XCTest
@testable import xpmenvkit

final class SettingsTests: XCTestCase {
    func test_coding_keys() {
        XCTAssertEqual(Settings.CodingKeys.lastTimeUpdatesChecked.rawValue, "last_time_updates_checked")
        XCTAssertEqual(Settings.CodingKeys.canaryReference.rawValue, "canary_reference")
    }

    func test_equatable() {
        let date = Date()
        let settingsA = Settings(lastTimeUpdatesChecked: date, canaryReference: "ref")
        let settingsB = Settings(lastTimeUpdatesChecked: date, canaryReference: "ref")
        XCTAssertEqual(settingsA, settingsB)
    }
}
