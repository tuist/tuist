import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class CacheProfileContentHasherTests: TuistUnitTestCase {
    private var subject: CacheProfileContentHasher!
    private var mockContentHasher: MockContentHasher!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = CacheProfileContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    func test_hash_callsContentHasherWithExpectedStrings() throws {
        // When
        let cacheProfile = TuistGraph.Cache.Profile(name: "Development", configuration: "Debug")

        // Then
        let hash = try subject.hash(cacheProfile: cacheProfile)
        XCTAssertEqual(hash, "Development;Debug")
        XCTAssertEqual(mockContentHasher.hashStringsCallCount, 1)
    }
}
