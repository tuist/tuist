import Foundation
import TuistCache
import TuistCore
import TuistCoreTesting
import TuistGenerator
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class GraphMapperProviderTests: TuistUnitTestCase {
    var subject: GraphMapperProvider!

    override func setUp() {
        super.setUp()
        subject = GraphMapperProvider(useCache: false)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_mappers_returns_theCacheMapper_when_useCache_is_true() {
        // Given
        subject = GraphMapperProvider(useCache: true)

        // when
        let got = subject.mappers(config: Config.test())

        // Then
        XCTAssertEqual(got.filter { $0 is CacheMapper }.count, 1)
    }

    func test_mappers_doesnt_return_theCacheMapper_when_useCache_is_false() {
        // Given
        subject = GraphMapperProvider(useCache: false)

        // when
        let got = subject.mappers(config: Config.test())

        // Then
        XCTAssertEqual(got.filter { $0 is CacheMapper }.count, 0)
    }

    func test_mappers_order() {
        // Given
        let mappers = subject.mappers(config: Config.test())

        // Then
        assert(mapper: DeleteDerivedDirectoryGraphMapper.self, isBeforeThan: GenerateInfoPlistGraphMapper.self, mappers: mappers)
        assert(mapper: GenerateInfoPlistGraphMapper.self, isBeforeThan: CacheMapper.self, mappers: mappers)
    }

    fileprivate func assert<T: GraphMapping, R: GraphMapping>(mapper _: T.Type,
                                                              isBeforeThan _: R.Type,
                                                              mappers: [GraphMapping],
                                                              file _: StaticString = #file,
                                                              line _: UInt = #line) {
        var firstFound = false

        for _mapper in mappers {
            if _mapper is T {
                firstFound = true
            }
            if _mapper is R {
                if !firstFound {
                    XCTFail("\(R.self) found before \(T.self)")
                }
            }
        }
    }
}
