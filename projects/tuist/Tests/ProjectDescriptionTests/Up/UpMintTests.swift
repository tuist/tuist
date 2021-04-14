import Foundation
import XCTest

@testable import ProjectDescription
@testable import TuistSupportTesting

final class UpMintTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = UpMint(linkPackagesGlobally: true)

        // Then
        XCTAssertCodable(subject)
    }
}
