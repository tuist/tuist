import Foundation
import Utility
@testable import xcbuddykit
import XCTest

final class CreateIssueCommandTests: XCTestCase {
    var shell: MockShell!
    var subject: CreateIssueCommand!

    override func setUp() {
        super.setUp()
        shell = MockShell()
        let context = CommandsContext(shell: shell)
        subject = CreateIssueCommand(context: context)
    }

    func test_command() {
        XCTAssertEqual(CreateIssueCommand.command, "create-issue")
    }

    func test_overview() {
        XCTAssertEqual(CreateIssueCommand.overview, "Opens the GitHub page to create a new issue.")
    }

    func test_run() throws {
        try subject.run(with: ArgumentParser.Result.test())
        XCTAssertEqual(shell.runArgs.first, ["open", CreateIssueCommand.createIssueUrl])
    }
}
