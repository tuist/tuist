import Foundation
import SPMUtility
import XCTest
@testable import TuistSupportTesting
@testable import TuistKit

final class CreateIssueCommandTests: TuistUnitTestCase {
    var subject: CreateIssueCommand!

    override func setUp() {
        super.setUp()
        let parser = ArgumentParser.test()

        subject = CreateIssueCommand(parser: parser)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
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
