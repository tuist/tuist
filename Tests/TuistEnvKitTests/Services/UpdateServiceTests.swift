import Foundation
import TuistSupport
import XCTest

@testable import TuistEnvKit
@testable import TuistSupportTesting

final class UpdateServiceTests: TuistUnitTestCase {
    var subject: UpdateService!
    var updater: MockUpdater!

    override func setUp() {
        super.setUp()
        updater = MockUpdater()
        subject = UpdateService(updater: updater)
    }

    override func tearDown() {
        updater = nil
        subject = nil
        super.tearDown()
    }

    func test_run() throws {
        var updateCallsCount: UInt = 0
        updater.updateStub = {
            updateCallsCount += 1
        }

        try subject.run()

        XCTAssertPrinterOutputContains("Checking for updates...")
        XCTAssertEqual(updateCallsCount, 1)
    }
}
