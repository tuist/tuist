import TestCoverageAttribution
import Testing
@testable import TuistCache

@Suite(.coverageAttribution)
struct CacheVersionFetcherTests {
    @Test func returnsCurrentArtifactFormatVersion() {
        #expect(CacheVersionFetcher().version() == .version9)
    }
}
