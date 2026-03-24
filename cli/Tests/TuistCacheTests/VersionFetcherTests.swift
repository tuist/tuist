import Foundation
import Testing
import TuistTesting

@testable import TuistCache

struct CacheVersionFetcherTests {
    @Test
    func return_the_right_version() {
        // Given
        let subject = CacheVersionFetcher()

        // When
        let got = subject.version()

        // Then
        #expect(got == .version5)
    }
}
