import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class PackageTests: TuistUnitTestCase {
    func test_codable_local() {
        // Given
        let subject = Package.local(path: "/path/to/package")
        
        // Then
        XCTAssertCodable(subject)
    }
    
    func test_codable_remote() {
        // Given
        let subject = Package.remote(
            url: "/url/to/package",
            requirement: .branch("branch")
        )
        
        // Then
        XCTAssertCodable(subject)
    }
}
