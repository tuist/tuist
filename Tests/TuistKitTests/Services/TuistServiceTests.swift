import XCTest
import TuistSupport
import TuistSupportTesting

@testable import TuistKit

final class TuistServiceTests: TuistUnitTestCase {
    var subject: TuistService!

    override func setUp() {
        super.setUp()
        subject = TuistService()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }
    
    func test_run() throws {
        system.succeedCommand("tuist-my-command", "argument-one")
        XCTAssertNoThrow(
            try subject.run(["my-command", "argument-one"])
        )
    }
}
