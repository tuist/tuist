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

    func test_toJSON_whenWatchOS() {
        let subject = DeploymentTarget.watchOS(targetVersion: "6.0")
        let expected = "{\"kind\":\"watchOS\",\"version\":\"6.0\"}"
        XCTAssertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_whenTVOS() {
        let subject = DeploymentTarget.tvOS(targetVersion: "14.2")
        let expected = "{\"kind\":\"tvOS\",\"version\":\"14.2\"}"
        XCTAssertCodableEqualToJson(subject, expected)
    }
}
