import Foundation
import Path
import TuistSupport
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class MacAddressProviderTests: TuistUnitTestCase {
    var subject: MacAddressProvider!

    override func setUp() {
        super.setUp()
        subject = MacAddressProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_macAddress_returnsANonEmptyAddress() throws {
        // When/Given
        let got = try subject.macAddress()

        // Then
        XCTAssertNotEqual(got, "")
    }
}
