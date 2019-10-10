import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class SettingsControllerTests: TuistUnitTestCase {
    var subject: SettingsController!

    override func setUp() {
        super.setUp()

        subject = SettingsController()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_settings_returns_the_default_settings_if_they_havent_been_set() throws {
        try XCTAssertEqual(subject.settings(), Settings())
    }
}
