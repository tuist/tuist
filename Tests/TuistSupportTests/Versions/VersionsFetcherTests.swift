import Foundation
import TuistSupport
import XCTest
@testable import TuistSupportTesting

final class VersionsFetcherTests: TuistUnitTestCase {
    var subject: VersionsFetcher!

    override func setUp() {
        subject = VersionsFetcher()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_fetch() throws {
        // When
        XCTAssertNoThrow(try subject.fetch())
    }
}
