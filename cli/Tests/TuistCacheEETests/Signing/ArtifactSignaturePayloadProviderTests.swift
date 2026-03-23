import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import Testing

@testable import TuistCacheEE

struct ArtifactSignaturePayloadProviderTests {
    let subject: ArtifactSignaturePayloadProvider
    init() {
        subject = ArtifactSignaturePayloadProvider()
    }


    @Test
    func test_fetch_returnsAPayloadWithNonEmptyMacAddress() throws {
        // Given/When
        let got = try subject.fetch()

        // Then
        #expect(got.macAddress != "")
    }
}
