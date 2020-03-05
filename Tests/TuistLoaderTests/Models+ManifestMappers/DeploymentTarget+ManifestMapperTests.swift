import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class DeploymentTargetManifestMapperTests: TuistUnitTestCase {
    func test_deploymentTarget() throws {
        // Given
        let manifest: ProjectDescription.DeploymentTarget = .iOS(targetVersion: "13.1", devices: .iphone)

        // When
        let got = TuistCore.DeploymentTarget.from(manifest: manifest)

        // Then
        guard
            case let .iOS(version, devices) = got
        else {
            XCTFail("Deployment target should be iOS")
            return
        }

        XCTAssertEqual(version, "13.1")
        XCTAssertTrue(devices.contains(.iphone))
        XCTAssertFalse(devices.contains(.ipad))
    }
}
