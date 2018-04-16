import Foundation
@testable import xcbuddykit
import XCTest

final class UpdateCommandTests: XCTestCase {
    var subject: UpdateCommand!
    var updateController: MockUpdateController!

    override func setUp() {
        super.setUp()
        updateController = MockUpdateController()
        subject = UpdateCommand(controller: updateController)
    }

    func test_name_returns_the_right_value() {
        XCTAssertEqual(subject.name, "update")
    }

    func test_shortDescription_returns_the_right_value() {
        XCTAssertEqual(subject.shortDescription, "Updates the app")
    }

    func test_execute_delegates_the_action_to_the_controller() throws {
        try subject.execute()
        XCTAssertEqual(updateController.checkAndUpdateFromConsoleCount, 1)
    }
}
