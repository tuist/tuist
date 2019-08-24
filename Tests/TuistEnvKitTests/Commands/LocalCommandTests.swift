import Basic
import Foundation
import TuistCore
import XCTest
@testable import SPMUtility
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class LocalCommandTests: XCTestCase {
    var argumentParser: ArgumentParser!
    var subject: LocalCommand!
    var fileHandler: MockFileHandler!
    var versionController: MockVersionsController!

    override func setUp() {
        super.setUp()
        mockEnvironment()
        fileHandler = sharedMockFileHandler()

        argumentParser = ArgumentParser(usage: "test", overview: "overview")
        versionController = try! MockVersionsController()
        subject = LocalCommand(parser: argumentParser, versionController: versionController)
    }

    func test_command() {
        XCTAssertEqual(LocalCommand.command, "local")
    }

    func test_overview() {
        XCTAssertEqual(LocalCommand.overview, "Creates a .tuist-version file to pin the tuist version that should be used in the current directory. If the version is not specified, it prints the local versions")
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

        XCTAssertPrinterOutputContains("""
        Generating \(Constants.versionFileName) file with version 3.2.1
        File generated at path \(versionPath.pathString)
        """)
    }

    func test_run_prints_when_no_argument_is_passed() throws {
        let result = try argumentParser.parse(["local"])
        versionController.semverVersionsStub = [Version(string: "1.2.3")!, Version(string: "3.2.1")!]
        try subject.run(with: result)

        XCTAssertPrinterOutputContains("""
        The following versions are available in the local environment:
        - 3.2.1
        - 1.2.3
        """)
    }
}
