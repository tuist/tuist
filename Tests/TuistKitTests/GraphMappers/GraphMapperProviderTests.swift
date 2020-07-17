import Foundation
import TuistCache
import TuistScale
import TuistCore
import TuistCoreTesting
import TuistGenerator
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

    func test_mappers_returns_cloud_insights_mapper_when_insights_option_is_passed() {
        // Given
        subject = GraphMapperProvider(cache: false)

        // When
        let got = subject.mappers(config: Config.test(cloud: .test(options: [.insights])))

        // Then
        XCTAssertEqual(got.filter { $0 is CloudInsightsGraphMapper }.count, 1)
    }

    func test_mappers_doesnt_return_cloud_insights_mapper_when_insights_option_is_passed() {
        // Given
        subject = GraphMapperProvider(cache: false)

        // When
        let got = subject.mappers(config: Config.test(cloud: .test(options: [])))

        // Then
        XCTAssertEqual(got.filter { $0 is CloudInsightsGraphMapper }.count, 0)
    }
}
