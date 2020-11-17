import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class CarthageDependencyManifestMapperTests: TuistUnitTestCase {
    func test_carthageDependency() {
        // Given
        let manifest: ProjectDescription.Dependency = .carthage(name: "Dependency", requirement: .exact("1.1.1"))
        
        // When
        let model = TuistCore.CarthageDependency.from(manifest: manifest)
        
        // Then
        XCTAssertEqual(model.name, "Dependency")
        XCTAssertEqual(model.requirement, .exact("1.1.1"))
    }
}
