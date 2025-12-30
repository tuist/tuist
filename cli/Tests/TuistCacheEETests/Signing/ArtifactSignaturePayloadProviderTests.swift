import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistCacheEE

final class ArtifactSignaturePayloadProviderTests: TuistUnitTestCase {
    var subject: ArtifactSignaturePayloadProvider!

    override func setUp() {
        super.setUp()
        subject = ArtifactSignaturePayloadProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_fetch_returnsAPayloadWithNonEmptyMacAddress() throws {
        // Given/When
        let got = try subject.fetch()

        // Then
        XCTAssertNotEqual(got.macAddress, "")
    }
}
