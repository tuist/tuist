import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class CarthageVersionFileTests: TuistUnitTestCase {
    func test_codable_alamofire() {
        // Given
        let json = CarthageVersionFile.testAlamofireJson
        let expected = CarthageVersionFile.testAlamofire
        
        // Then / When
        XCTAssertDecodableEqualToJson(json, expected)
    }
    
    func test_codable_rxSwift() {
        // Given
        let json = CarthageVersionFile.testRxSwiftJson
        let expected = CarthageVersionFile.testRxSwift
        
        // Then / When
        XCTAssertDecodableEqualToJson(json, expected)
    }
}
