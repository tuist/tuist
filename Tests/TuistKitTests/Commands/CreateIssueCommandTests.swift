import Foundation
import SPMUtility
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class CreateIssueCommandTests: XCTestCase {
    var system: MockSystem!
    var subject: CreateIssueCommand!

    override func setUp() {
        super.setUp()
        system = MockSystem()
        subject = CreateIssueCommand(system: system)
    }

    func test_command() {
        XCTAssertEqual(CreateIssueCommand.command, "create-issue")
    }

    func test_overview() {
        XCTAssertEqual(CreateIssueCommand.overview, "Opens the GitHub page to create a new issue.")
    }

    func test_run() throws {
        system.succeedCommand("/usr/bin/open", CreateIssueCommand.createIssueUrl)
        try subject.run(with: ArgumentParser.Result.test())
    }
}
