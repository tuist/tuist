import Foundation
import Path
import XcodeProj
import XCTest

@testable import TuistGenerator

final class TestPlanGeneratorTests: XCTestCase {
    func test_encode_produces_valid_xctestplan_json() throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "AppTests")
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                TestPlanDescriptor.TestTarget(
                    pbxTarget: pbxTarget,
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true
                ),
            ]
        )

        // When
        let data = try TestPlanGenerator.encode(descriptor)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        XCTAssertEqual(json?["version"] as? Int, 1)
        let testTargets = try XCTUnwrap(json?["testTargets"] as? [[String: Any]])
        XCTAssertEqual(testTargets.count, 1)
        let target = try XCTUnwrap(testTargets.first?["target"] as? [String: String])
        XCTAssertEqual(target["containerPath"], "container:App.xcodeproj")
        XCTAssertEqual(target["name"], "AppTests")
        XCTAssertNotNil(target["identifier"])
        XCTAssertNil(testTargets.first?["enabled"]) // enabled omitted when true
    }

    func test_encode_marks_disabled_targets() throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "AppTests")
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                TestPlanDescriptor.TestTarget(
                    pbxTarget: pbxTarget,
                    containerPath: "container:App.xcodeproj",
                    isEnabled: false
                ),
            ]
        )

        // When
        let data = try TestPlanGenerator.encode(descriptor)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        let testTargets = try XCTUnwrap(json?["testTargets"] as? [[String: Any]])
        XCTAssertEqual(testTargets.first?["enabled"] as? Bool, false)
    }
}
