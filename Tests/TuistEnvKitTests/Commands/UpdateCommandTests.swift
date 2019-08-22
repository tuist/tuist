import Foundation
import TuistCore
import XCTest

@testable import SPMUtility
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class UpdateCommandTests: XCTestCase {
    var parser: ArgumentParser!
    var subject: UpdateCommand!
    var updater: MockUpdater!

    override func setUp() {
        super.setUp()
        mockEnvironment()

        parser = ArgumentParser(usage: "test", overview: "overview")
        updater = MockUpdater()
        subject = UpdateCommand(parser: parser,
                                updater: updater)
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

        XCTAssertPrinterOutputContains("Checking for updates...")
        XCTAssertEqual(updateCalls, [true])
    }
}
