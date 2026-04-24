import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
import XcodeProj

struct TestPlanDescriptorTests {
    @Test func encode_produces_valid_xctestplan_json() throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "AppTests")
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                TestPlanDescriptor.TestTarget(
                    pbxTarget: pbxTarget,
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true,
                    parallelization: .swiftTestingOnly
                ),
            ]
        )

        // When
        let data = try descriptor.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        #expect(json?["version"] as? Int == 1)
        let testTargets = try #require(json?["testTargets"] as? [[String: Any]])
        #expect(testTargets.count == 1)
        let target = try #require(testTargets.first?["target"] as? [String: String])
        #expect(target["containerPath"] == "container:App.xcodeproj")
        #expect(target["name"] == "AppTests")
        #expect(target["identifier"] != nil)
        #expect(testTargets.first?["enabled"] == nil) // enabled omitted when true
        #expect(testTargets.first?["parallelizable"] == nil) // swiftTestingOnly omits the field
    }

    @Test func encode_configuration_id_is_deterministic_per_path() throws {
        // Given
        let target = PBXNativeTarget(name: "AppTests")
        func descriptor(at pathString: String) throws -> TestPlanDescriptor {
            TestPlanDescriptor(
                path: try AbsolutePath(validating: pathString),
                testTargets: [
                    .init(
                        pbxTarget: target,
                        containerPath: "container:App.xcodeproj",
                        isEnabled: true,
                        parallelization: .swiftTestingOnly
                    ),
                ]
            )
        }

        // When
        let firstRun = try JSONSerialization.jsonObject(with: try descriptor(at: "/tmp/A.xctestplan").encode())
        let secondRun = try JSONSerialization.jsonObject(with: try descriptor(at: "/tmp/A.xctestplan").encode())
        let differentPath = try JSONSerialization.jsonObject(with: try descriptor(at: "/tmp/B.xctestplan").encode())

        // Then
        func configurationID(_ object: Any) throws -> String {
            let dict = try #require(object as? [String: Any])
            let configurations = try #require(dict["configurations"] as? [[String: Any]])
            return try #require(configurations.first?["id"] as? String)
        }

        #expect(try configurationID(firstRun) == configurationID(secondRun))
        #expect(try configurationID(firstRun) != configurationID(differentPath))
    }

    @Test func encode_marks_disabled_targets() throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "AppTests")
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                TestPlanDescriptor.TestTarget(
                    pbxTarget: pbxTarget,
                    containerPath: "container:App.xcodeproj",
                    isEnabled: false,
                    parallelization: .swiftTestingOnly
                ),
            ]
        )

        // When
        let data = try descriptor.encode()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Then
        let testTargets = try #require(json?["testTargets"] as? [[String: Any]])
        #expect(testTargets.first?["enabled"] as? Bool == false)
    }

    @Test func encode_parallelization_writes_parallelizable_field() throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "AppTests")
        func descriptor(parallelization: TestableTarget.Parallelization) throws -> TestPlanDescriptor {
            TestPlanDescriptor(
                path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
                testTargets: [
                    .init(
                        pbxTarget: pbxTarget,
                        containerPath: "container:App.xcodeproj",
                        isEnabled: true,
                        parallelization: parallelization
                    ),
                ]
            )
        }

        func parallelizable(_ plan: TestPlanDescriptor) throws -> Any? {
            let data = try plan.encode()
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let testTargets = try #require(json?["testTargets"] as? [[String: Any]])
            return testTargets.first?["parallelizable"]
        }

        // Then
        #expect(try parallelizable(descriptor(parallelization: .all)) as? Bool == true)
        #expect(try parallelizable(descriptor(parallelization: .none)) as? Bool == false)
        #expect(try parallelizable(descriptor(parallelization: .swiftTestingOnly)) == nil)
    }
}
