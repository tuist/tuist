import Foundation
import Path
import Testing
import TuistSupport

@testable import TuistCacheEE
@testable import TuistTesting

struct MacAddressProviderTests {
    let subject: MacAddressProvider
    init() {
        subject = MacAddressProvider()
    }

    @Test
    func macAddress_returnsANonEmptyAddress() throws {
        // When/Given
        let got = try subject.macAddress()

        // Then
        #expect(got != "")
    }
}
