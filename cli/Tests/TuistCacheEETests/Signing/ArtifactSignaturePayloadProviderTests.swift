import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistCacheEE

struct ArtifactSignaturePayloadProviderTests {
    let subject: ArtifactSignaturePayloadProvider
    init() {
        subject = ArtifactSignaturePayloadProvider()
    }

    @Test
    func fetch_returnsAPayloadWithNonEmptyMacAddress() throws {
        // Given/When
        let got = try subject.fetch()

        // Then
        #expect(got.macAddress != "")
    }
}
