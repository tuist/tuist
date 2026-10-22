import Testing
@testable import TuistCache

struct CacheVersionFetcherTests {
    @Test func returnsCurrentArtifactFormatVersion() {
        #expect(CacheVersionFetcher().version() == .version9)
    }
}
