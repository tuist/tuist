import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class RequirementManifestMapperTests: TuistUnitTestCase {
    func test_requirement_exact() {
        // Given
        let manifest = ProjectDescription.Dependency.Requirement.exact("1.1.1")
        
        // When
        let model = TuistCore.Requirement.from(manifest: manifest)
        
        // Then
        XCTAssertEqual(model, .exact("1.1.1"))
    }
}
