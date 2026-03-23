import Foundation
import Path
import TuistSupport
import Testing

@testable import TuistCacheEE
@testable import TuistTesting

struct MacAddressProviderTests {
    let subject: MacAddressProvider
    init() {
        subject = MacAddressProvider()
    }


    @Test
    func test_macAddress_returnsANonEmptyAddress() throws {
        // When/Given
        let got = try subject.macAddress()

        // Then
        #expect(got != "")
    }
}
