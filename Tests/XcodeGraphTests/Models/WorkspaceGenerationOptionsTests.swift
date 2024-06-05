import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class WorkspaceGenerationOptionsTests: TuistUnitTestCase {
    func test_codable_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.test()

        // Then
        XCTAssertCodable(subject)
    }
}
