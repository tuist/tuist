import Foundation
import TuistTesting
import Testing

@testable import TuistCache

struct CacheVersionFetcherTests {
    @Test
    func test_return_the_right_version() {
        // Given
        let subject = CacheVersionFetcher()

        // When
        let got = subject.version()

        // Then
        #expect(got == .version5)
    }
}
