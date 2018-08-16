import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistKit
import Utility
import XCTest

final class CommandCheckErrorTests: XCTestCase {
    func test_errorDescription_when_swiftVersionNotFound() {
        let error = CommandCheckError.swiftVersionNotFound
        var expected = "Error getting your Swift version."
        expected.append(" Make sure 'swift' is available from your shell and that 'swift version' returns the language version")
        XCTAssertEqual(error.description, expected)
    }

    func test_errorDescription_when_incompatibleSwiftVersion() {
        let error = CommandCheckError.incompatibleSwiftVersion(system: "4.0", expected: "4.1")
        var expected = "The Swift version in your system, 4.0 is incompatible with the version tuist expects 4.1"
        expected.append(" If you updated Xcode recently, update tuist to the lastest version.")
        XCTAssertEqual(error.description, expected)
    }
}

final class CommandCheckTests: XCTestCase {
    var system: MockSystem!
    var subject: CommandCheck!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        subject = CommandCheck(system: system)
    }

    func test_checkableCommands() {
        XCTAssertEqual(CommandCheck.checkableCommands(), [
            DumpCommand.command,
            GenerateCommand.command,
        ])
    }
}
