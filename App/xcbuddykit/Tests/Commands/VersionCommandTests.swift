import Basic
import Foundation
import Utility
@testable import xcbuddykit
import XCTest

final class VersionCommandTests: XCTestCase {
    var printer: MockPrinter!
    var subject: VersionCommand!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        let context = CommandsContext(printer: printer)
        subject = VersionCommand(context: context,
                                 version: { "0.1.0" })
    }

    func test_command() {
        XCTAssertEqual(VersionCommand.command, "version")
    }

    func test_description() {
        XCTAssertEqual(VersionCommand.overview, "Outputs the current version of xcbuddy.")
    }

    func test_run() {
        let arguments = ArgumentParser.Result.test()
        subject.run(with: arguments)
        XCTAssertEqual(printer.printArgs.first, "0.1.0")
    }
}
