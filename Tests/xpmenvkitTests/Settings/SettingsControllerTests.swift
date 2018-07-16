import Basic
import Foundation
import XCTest
@testable import xpmenvkit

final class SettingsControllerTests: XCTestCase {
    var subject: SettingsController!
    var environmentController: MockEnvironmentController!

    override func setUp() {
        super.setUp()
        environmentController = try! MockEnvironmentController()
        subject = SettingsController(environmentController: environmentController)
    }

    func test_settings_returns_the_default_settings_if_they_havent_been_set() throws {
        try XCTAssertEqual(subject.settings(), Settings())
    }

    func test_set_settings_stores_the_settings() throws {
        let settings = try subject.settings()
        settings.canaryReference = "reference"
        try subject.set(settings: settings)
        let got = try subject.settings()
        XCTAssertEqual(got.canaryReference, "reference")
    }

    func test_set_settings_stores_the_settings_at_the_right_path() throws {
        let settings = try subject.settings()
        settings.canaryReference = "reference"
        try subject.set(settings: settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: environmentController.settingsPath.asString))
    }
}
