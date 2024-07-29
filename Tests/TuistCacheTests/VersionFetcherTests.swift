import Foundation
import Path
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistCache

final class CacheVersionFetcherTests: TuistUnitTestCase {
    func test_return_the_right_version() {
        // Given
        let subject = CacheVersionFetcher()

        // When
        let got = subject.version()

        // Then
        XCTAssertEqual(got, .version2)
    }
}
