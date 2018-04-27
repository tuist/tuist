import Foundation
import Utility
@testable import xcbuddykit
import XCTest

final class UpdateCommandTests: XCTestCase {
    var updateController: MockUpdateController!
    var subject: UpdateCommand!

    override func setUp() {
        super.setUp()
        updateController = MockUpdateController()
        subject = UpdateCommand(controller: updateController)
    }

    func test_command() {
        XCTAssertEqual(subject.command, "update")
    }

    func test_overview() {
        XCTAssertEqual(subject.overview, "Updates the app.")
    }

    func test_run() throws {
        let result = ArgumentParser.Result.test()
        try subject.run(with: result)
        XCTAssertEqual(updateController.checkAndUpdateFromConsoleCount, 1)
    }
}
