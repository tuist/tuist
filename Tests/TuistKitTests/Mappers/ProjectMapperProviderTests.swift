import Foundation
import TuistCache
import TuistCore
import TuistCoreTesting
import TuistGenerator
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ProjectMapperProviderTests: TuistUnitTestCase {
    var subject: ProjectMapperProvider!

    override func setUp() {
        super.setUp()
        subject = ProjectMapperProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_mappers_order() {
        // Given
        let mappers = subject.mappers(config: Config.test())

        // Then
        assert(mapper: DeleteDerivedDirectoryProjectMapper.self, isBeforeThan: GenerateInfoPlistProjectMapper.self, mappers: mappers)
    }

    // MARK: - Helpers

    private func assert<T: ProjectMapping, R: ProjectMapping>(mapper _: T.Type,
                                                              isBeforeThan _: R.Type,
                                                              mappers: [ProjectMapping],
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
