import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistEnvKit

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
}
