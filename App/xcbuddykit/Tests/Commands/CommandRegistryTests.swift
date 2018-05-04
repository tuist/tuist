import Foundation
@testable import xcbuddykit
import XCTest

final class CommandRegistryTests: XCTestCase {
    var subject: CommandRegistry!
    var command: MockCommand!

    override func setUp() {
        super.setUp()
        subject = CommandRegistry { ["xcbuddy", "command"] }
        subject.register(command: MockCommand.self)
        command = subject.commands.last! as! MockCommand
    }

    func test_run() throws {
        try subject.run()
        XCTAssertEqual(command.runArgs.count, 1)
    }
}
