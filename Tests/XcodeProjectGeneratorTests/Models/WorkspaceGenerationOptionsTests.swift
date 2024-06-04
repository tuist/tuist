import Foundation
import XCTest

@testable import XcodeProjectGenerator
@testable import TuistSupportTesting

final class WorkspaceGenerationOptionsTests: TuistUnitTestCase {
    func test_codable_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.test()

        // Then
        XCTAssertCodable(subject)
    }
}
