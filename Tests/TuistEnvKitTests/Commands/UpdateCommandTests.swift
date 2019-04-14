import Foundation
import XCTest

@testable import TuistCoreTesting
@testable import TuistEnvKit
@testable import SPMUtility

final class UpdateCommandTests: XCTestCase {
    var parser: ArgumentParser!
    var subject: UpdateCommand!
    var updater: MockUpdater!
    var printer: MockPrinter!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser(usage: "test", overview: "overview")
        updater = MockUpdater()
        printer = MockPrinter()
        subject = UpdateCommand(parser: parser,
                                updater: updater,
                                printer: printer)
    }

    func test_command() {
        XCTAssertEqual(UpdateCommand.command, "update")
    }

    func test_overview() {
        XCTAssertEqual(UpdateCommand.overview, "Installs the latest version if it's not already installed")
    }

    func test_init_registers_the_command() {
        XCTAssertEqual(parser.subparsers.count, 1)
        XCTAssertEqual(parser.subparsers.first?.key, UpdateCommand.command)
        XCTAssertEqual(parser.subparsers.first?.value.overview, UpdateCommand.overview)
    }

    func test_run() throws {
        let result = try parser.parse(["update", "-f"])

        var updateCalls: [Bool] = []
        updater.updateStub = { force in
            updateCalls.append(force)
        }

        try subject.run(with: result)

        XCTAssertEqual(printer.printSectionArgs, ["Checking for updates..."])
        XCTAssertEqual(updateCalls, [true])
    }
}
