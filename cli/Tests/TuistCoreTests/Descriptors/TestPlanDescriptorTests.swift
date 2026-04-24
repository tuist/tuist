import Foundation
import Path
import TuistCore
import XcodeProj
import XCTest

final class TestPlanDescriptorTests: XCTestCase {
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
        let data = try descriptor.encode()
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

    func test_encode_configuration_id_is_deterministic_per_path() throws {
        // Given
        let target = PBXNativeTarget(name: "AppTests")
        func descriptor(at pathString: String) throws -> TestPlanDescriptor {
            TestPlanDescriptor(
                path: try AbsolutePath(validating: pathString),
                testTargets: [
                    .init(pbxTarget: target, containerPath: "container:App.xcodeproj", isEnabled: true),
                ]
            )
        }

        // When
        let firstRun = try JSONSerialization.jsonObject(with: try descriptor(at: "/tmp/A.xctestplan").encode())
        let secondRun = try JSONSerialization.jsonObject(with: try descriptor(at: "/tmp/A.xctestplan").encode())
        let differentPath = try JSONSerialization.jsonObject(with: try descriptor(at: "/tmp/B.xctestplan").encode())

        // Then
        func configurationID(_ object: Any) throws -> String {
            let dict = try XCTUnwrap(object as? [String: Any])
            let configurations = try XCTUnwrap(dict["configurations"] as? [[String: Any]])
            return try XCTUnwrap(configurations.first?["id"] as? String)
        }

        XCTAssertEqual(try configurationID(firstRun), try configurationID(secondRun))
        XCTAssertNotEqual(try configurationID(firstRun), try configurationID(differentPath))
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
        let data = try descriptor.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        let testTargets = try XCTUnwrap(json?["testTargets"] as? [[String: Any]])
        XCTAssertEqual(testTargets.first?["enabled"] as? Bool, false)
    }
}
