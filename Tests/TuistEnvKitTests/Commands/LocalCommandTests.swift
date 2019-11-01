import Basic
import Foundation
import TuistSupport
import XCTest
@testable import SPMUtility
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class LocalCommandTests: TuistUnitTestCase {
    var argumentParser: ArgumentParser!
    var subject: LocalCommand!
    var versionController: MockVersionsController!

    override func setUp() {
        super.setUp()

        argumentParser = ArgumentParser(usage: "test", overview: "overview")
        versionController = try! MockVersionsController()
        subject = LocalCommand(parser: argumentParser, versionController: versionController)
    }

    override func tearDown() {
        argumentParser = nil
        subject = nil
        versionController = nil

        super.tearDown()
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
        let temporaryPath = try self.temporaryPath()
        let result = try argumentParser.parse(["local", "3.2.1"])
        try subject.run(with: result)

        let versionPath = temporaryPath.appending(component: Constants.versionFileName)

        XCTAssertEqual(try String(contentsOf: versionPath.url), "3.2.1")
    }

    func test_run_prints_when_version_argument_is_passed() throws {
        let temporaryPath = try self.temporaryPath()
        let result = try argumentParser.parse(["local", "3.2.1"])
        try subject.run(with: result)

        let versionPath = temporaryPath.appending(component: Constants.versionFileName)

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
