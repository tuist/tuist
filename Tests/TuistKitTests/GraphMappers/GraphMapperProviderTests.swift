import Foundation
import TuistCache
import TuistCore
import TuistCoreTesting
import TuistGenerator
import TuistScale
import TuistSigning
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class GraphMapperProviderTests: TuistUnitTestCase {
    var subject: GraphMapperProvider!

    override func setUp() {
        super.setUp()
        subject = GraphMapperProvider(cache: false)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_mappers_returns_theCacheMapper_when_useCache_is_true() {
        // Given
        subject = GraphMapperProvider(cache: true)

        // when
        let got = subject.mappers(config: Config.test())

        // Then
        XCTAssertEqual(got.filter { $0 is CacheMapper }.count, 1)
    }

    func test_mappers_doesnt_return_theCacheMapper_when_useCache_is_false() {
        // Given
        subject = GraphMapperProvider(cache: false)

        // when
        let got = subject.mappers(config: Config.test())

        // Then
        XCTAssertEqual(got.filter { $0 is CacheMapper }.count, 0)
    }
}
