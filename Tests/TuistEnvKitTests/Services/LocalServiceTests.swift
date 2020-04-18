import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistSupport
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class LocalServiceTests: TuistUnitTestCase {
    var subject: LocalService!
    var versionController: MockVersionsController!

    override func setUp() {
        super.setUp()

        versionController = try! MockVersionsController()
        subject = LocalService(versionController: versionController)
    }

    override func tearDown() {
        subject = nil
        versionController = nil

        super.tearDown()
    }

    func test_run_when_version_argument_is_passed() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        // When
        try subject.run(version: "3.2.1")

        // Then
        let versionPath = temporaryPath.appending(component: Constants.versionFileName)
        XCTAssertEqual(try String(contentsOf: versionPath.url), "3.2.1")
    }

    func test_run_prints_when_version_argument_is_passed() throws {
        // Given
        let temporaryPath = try self.temporaryPath()

        // When
        try subject.run(version: "3.2.1")

        // Then
        let versionPath = temporaryPath.appending(component: Constants.versionFileName)

        XCTAssertPrinterOutputContains("""
        Generating \(Constants.versionFileName) file with version 3.2.1
        File generated at path \(versionPath.pathString)
        """)
    }

    func test_run_prints_when_no_argument_is_passed() throws {
        // Given
        versionController.semverVersionsStub = [Version(string: "1.2.3")!, Version(string: "3.2.1")!]

        // When
        try subject.run(version: nil)

        // Then
        XCTAssertPrinterOutputContains("""
        The following versions are available in the local environment:
        - 3.2.1
        - 1.2.3
        """)
    }
}
