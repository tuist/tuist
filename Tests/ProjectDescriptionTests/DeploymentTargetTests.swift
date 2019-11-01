import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class DeploymentTargetTests: XCTestCase {
    func test_toJSON_whenIOS() {
        let subject = DeploymentTarget.iOS(targetVersion: "13.1", devices: [.iphone, .ipad])
        let expected = "{\"kind\":\"iOS\",\"version\":\"13.1\",\"deploymentDevices\":3}"
        XCTAssertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_whenMacOS() {
        let subject = DeploymentTarget.macOS(targetVersion: "10.15")
        let expected = "{\"kind\":\"macOS\",\"version\":\"10.15\"}"
        XCTAssertCodableEqualToJson(subject, expected)
    }
}
