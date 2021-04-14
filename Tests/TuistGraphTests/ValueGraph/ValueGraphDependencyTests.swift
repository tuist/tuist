import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ValueGraphDependencyTests: TuistUnitTestCase {
    func test_codable_target() {
        // Given
        let subject = ValueGraphDependency.testTarget()
        
        // Then
        XCTAssertCodable(subject)
    }
    
    func test_codable_framework() {
        // Given
        let subject = ValueGraphDependency.testFramework()
        
        // Then
        XCTAssertCodable(subject)
    }
}
