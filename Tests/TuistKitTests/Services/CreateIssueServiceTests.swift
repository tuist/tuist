import Foundation
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class CreateIssueServiceTests: TuistUnitTestCase {
    var subject: CreateIssueService!

    override func setUp() {
        super.setUp()

        subject = CreateIssueService()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_run() throws {
        system.succeedCommand("/usr/bin/open", CreateIssueService.createIssueUrl)
        try subject.run()
    }
}
