import Basic
import Foundation
import XCTest
@testable import xpmenvkit

final class SettingsControllerTests: XCTestCase {
    var subject: SettingsController!
    var environmentController: MockEnvironmentController!
    var versionsDirectory: AbsolutePath!
    var settingsPath: AbsolutePath!
    var tmpDir: TemporaryDirectory!

    override func setUp() {
        super.setUp()
        tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        versionsDirectory = tmpDir.path.appending(component: "Versions")
        settingsPath = tmpDir.path.appending(component: "settings.json")
        environmentController = MockEnvironmentController(versionsDirectory: versionsDirectory,
                                                          settingsPath: settingsPath)
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsPath.asString))
    }
}
