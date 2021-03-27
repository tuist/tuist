import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class PackageInfoTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = PackageInfo.test()
        
        // When
        XCTAssertCodable(subject)
    }
}
