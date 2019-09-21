import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class SettingsControllerTests: XCTestCase {
    var subject: SettingsController!
    var environment: MockEnvironment!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()

        environment = sharedMockEnvironment()
        subject = SettingsController()
    }

    func test_settings_returns_the_default_settings_if_they_havent_been_set() throws {
        try XCTAssertEqual(subject.settings(), Settings())
    }
}
