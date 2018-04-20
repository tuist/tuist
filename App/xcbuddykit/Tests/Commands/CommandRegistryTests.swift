import Foundation
@testable import xcbuddykit
import XCTest

final class CommandRegistryTests: XCTestCase {
    var subject: CommandRegistry!
    var command: MockCommand!

    override func setUp() {
        super.setUp()
        subject = CommandRegistry(usage: "usage",
                                  overview: "overview") { () -> [String] in
            ["binary", "command"]
        }
        subject.register(command: MockCommand.self)
        command = subject.commands.first! as! MockCommand
    }

    func test_run() throws {
        subject.run()
        XCTAssertEqual(command.runArgs.count, 1)
    }
}
