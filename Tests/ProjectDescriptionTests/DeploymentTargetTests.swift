import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class DeploymentTargetTests: XCTestCase {
    func test_toJSON_whenIOS() {
        let subject = DeploymentTarget.iOS("13.1", [.iphone, .ipad])
        let expected = "{\"kind\":\"iOS\",\"version\":\"13.1\",\"deploymentDevices\":[1,2]}"
        XCTAssertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_whenMacOS() {
        let subject = DeploymentTarget.macOS("10.15")
        let expected = "{\"kind\":\"macOS\",\"version\":\"10.15\"}"
        XCTAssertCodableEqualToJson(subject, expected)
    }
}
