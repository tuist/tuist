import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistEnvKit
@testable import Utility
import XCTest

final class LocalCommandTests: XCTestCase {
    var argumentParser: ArgumentParser!
    var subject: LocalCommand!
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!
    var versionController: MockVersionsController!

    override func setUp() {
        super.setUp()
        argumentParser = ArgumentParser(usage: "test", overview: "overview")
        printer = MockPrinter()
        fileHandler = try! MockFileHandler()
        versionController = try! MockVersionsController()
        subject = LocalCommand(parser: argumentParser,
                               fileHandler: fileHandler,
                               printer: printer,
                               versionController: versionController)
    }

    func test_command() {
        XCTAssertEqual(LocalCommand.command, "local")
    }

    func test_overview() {
        XCTAssertEqual(LocalCommand.overview, "Creates a .tuist-version file to pin the tuist version that should be used in the current directory. If the version is not specified, it prints the local versions.")
    }

    func test_init_registers_the_command() {
        XCTAssertEqual(argumentParser.subparsers.count, 1)
        XCTAssertEqual(argumentParser.subparsers.first?.key, LocalCommand.command)
        XCTAssertEqual(argumentParser.subparsers.first?.value.overview, LocalCommand.overview)
    }

    func test_run_when_version_argument_is_passed() throws {
        let result = try argumentParser.parse(["local", "3.2.1"])
        try subject.run(with: result)

        let versionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)

        XCTAssertEqual(try String(contentsOf: versionPath.url), "3.2.1")
    }

    func test_run_prints_when_version_argument_is_passed() throws {
        let result = try argumentParser.parse(["local", "3.2.1"])
        try subject.run(with: result)

        let versionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)

        XCTAssertEqual(printer.printSectionArgs.count, 1)
        XCTAssertEqual(printer.printSectionArgs.first, "Generating \(Constants.versionFileName) file with version 3.2.1")

        XCTAssertEqual(printer.printSuccessArgs.count, 1)
        XCTAssertEqual(printer.printSuccessArgs.last, "File generated at path \(versionPath.asString)")
    }

    func test_run_prints_when_no_argument_is_passed() throws {
        let result = try argumentParser.parse(["local"])
        versionController.semverVersionsStub = [Version("1.2.3"), Version("3.2.1")]
        try subject.run(with: result)

        XCTAssertEqual(printer.printSectionArgs.count, 1)
        XCTAssertEqual(printer.printSectionArgs.first, "The following versions are available in the local environment:")

        XCTAssertEqual(printer.printArgs.count, 1)
        XCTAssertEqual(printer.printArgs.last, "- 3.2.1\n- 1.2.3")
    }
}
