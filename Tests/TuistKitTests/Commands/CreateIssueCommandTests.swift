import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
import Utility
import XCTest

final class CreateIssueCommandTests: XCTestCase {
    var shell: MockShell!
    var subject: CreateIssueCommand!

    override func setUp() {
        super.setUp()
        shell = MockShell()
        subject = CreateIssueCommand(shell: shell)
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
