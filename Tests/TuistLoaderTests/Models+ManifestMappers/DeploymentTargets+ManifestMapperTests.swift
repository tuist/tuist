import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistSupportTesting

final class DeploymentTargetsManifestMapperTests: TuistUnitTestCase {
    func test_deploymentTarget() throws {
        // Given
        let manifest: ProjectDescription.DeploymentTarget = .iOS(targetVersion: "13.1", devices: .iphone)

        // When
        let got = ProjectDescription.DeploymentTargets.from(manifest: manifest)

        // Then
        XCTAssertEqual(got[.iOS], "13.1")
        XCTAssertNil(got[.macOS])
        XCTAssertNil(got[.watchOS])
        XCTAssertNil(got[.tvOS])
    }
}
