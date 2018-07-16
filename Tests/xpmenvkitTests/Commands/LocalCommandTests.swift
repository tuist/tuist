import Basic
import Foundation
@testable import Utility
import XCTest
import xpmcore
@testable import xpmcoreTesting
@testable import xpmenvkit

final class LocalCommandTests: XCTestCase {
    var argumentParser: ArgumentParser!
    var subject: LocalCommand!
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!

    override func setUp() {
        super.setUp()
        argumentParser = ArgumentParser(usage: "test", overview: "overview")
        printer = MockPrinter()
        fileHandler = try! MockFileHandler()
        subject = LocalCommand(parser: argumentParser,
                               fileHandler: fileHandler,
                               printer: printer)
    }

    func test_command() {
        XCTAssertEqual(LocalCommand.command, "local")
    }

    func test_overview() {
        XCTAssertEqual(LocalCommand.overview, "Creates a .xpm-version file to pin the xpm version that should be used in the current directory.")
    }

    func test_init_registers_the_command() {
        XCTAssertEqual(argumentParser.subparsers.count, 1)
        XCTAssertEqual(argumentParser.subparsers.first?.key, LocalCommand.command)
        XCTAssertEqual(argumentParser.subparsers.first?.value.overview, LocalCommand.overview)
    }

    func test_run() throws {
        let result = try argumentParser.parse(["local", "3.2.1"])
        try subject.run(with: result)

        let versionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)

        XCTAssertEqual(try String(contentsOf: versionPath.url), "3.2.1")
    }

    func test_run_prints() throws {
        let result = try argumentParser.parse(["local", "3.2.1"])
        try subject.run(with: result)

        let versionPath = fileHandler.currentPath.appending(component: Constants.versionFileName)

        XCTAssertEqual(printer.printSectionArgs.count, 1)
        XCTAssertEqual(printer.printSectionArgs.first, "Generating \(Constants.versionFileName) file with version 3.2.1.")

        XCTAssertEqual(printer.printSuccessArgs.count, 1)
        XCTAssertEqual(printer.printSuccessArgs.last, "File generated at path \(versionPath.asString).")
    }
}
