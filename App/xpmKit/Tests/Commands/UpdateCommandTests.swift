import Foundation
import Utility
import XCTest
@testable import xpmKit

final class UpdateCommandTests: XCTestCase {
    var updateController: MockUpdateController!
    var subject: UpdateCommand!
    var context: CommandsContexting!

    override func setUp() {
        super.setUp()
        updateController = MockUpdateController()
        context = CommandsContext()
        subject = UpdateCommand(controller: updateController,
                                context: context)
    }

    func test_command() {
        XCTAssertEqual(UpdateCommand.command, "update")
    }

    func test_overview() {
        XCTAssertEqual(UpdateCommand.overview, "Updates the app.")
    }

    func test_run() throws {
        let result = ArgumentParser.Result.test()
        try subject.run(with: result)
        XCTAssertEqual(updateController.checkAndUpdateFromConsoleCount, 1)
    }
}
