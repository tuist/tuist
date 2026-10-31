import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
import XcodeProj

struct TestPlanDescriptorTests {
    @Test func legacy_initializer_preserves_xcode_coverage_defaults() throws {
        let inferredFactory = TestPlanDescriptor.init
        let factory: (AbsolutePath, [TestPlanDescriptor.TestTarget]) -> TestPlanDescriptor = inferredFactory
        let descriptor = factory(try AbsolutePath(validating: "/tmp/Plan.xctestplan"), [])
        let json = try #require(JSONSerialization.jsonObject(with: descriptor.encode()) as? [String: Any])
        let options = try #require(json["defaultOptions"] as? [String: Any])
        #expect(options.isEmpty)
    }

    @Test(arguments: [false, true]) func encode_coverage_for_all_targets(coverage: Bool) throws {
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [],
            coverage: coverage
        )

        let json = try #require(JSONSerialization.jsonObject(with: descriptor.encode()) as? [String: Any])
        let options = try #require(json["defaultOptions"] as? [String: Any])
        if coverage {
            let coverageOptions = try #require(options["codeCoverage"] as? [String: Any])
            #expect(coverageOptions.isEmpty)
        } else {
            #expect(options["codeCoverage"] as? Bool == false)
        }
    }

    @Test(arguments: [false, true]) func encode_coverage_for_selected_targets(coverage: Bool) throws {
        let app = PBXNativeTarget(name: "App")
        let framework = PBXNativeTarget(name: "Framework")
        let descriptor = TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [],
            coverage: coverage,
            codeCoverageTargets: [
                .init(pbxTarget: app, containerPath: "container:App.xcodeproj"),
                .init(pbxTarget: framework, containerPath: "container:Frameworks/Framework.xcodeproj"),
            ]
        )

        let json = try #require(JSONSerialization.jsonObject(with: descriptor.encode()) as? [String: Any])
        let options = try #require(json["defaultOptions"] as? [String: Any])
        if coverage {
            let coverageOptions = try #require(options["codeCoverage"] as? [String: Any])
            let targets = try #require(coverageOptions["targets"] as? [[String: String]])
            #expect(targets == [
                ["containerPath": "container:App.xcodeproj", "identifier": app.uuid, "name": "App"],
                ["containerPath": "container:Frameworks/Framework.xcodeproj", "identifier": framework.uuid, "name": "Framework"],
            ])
        } else {
            #expect(options["codeCoverage"] as? Bool == false)
        }
    }

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

    @Test func encode_writes_language_and_region_into_default_options() throws {
        // Given
        func descriptor(language: String?, region: String?) throws -> TestPlanDescriptor {
            TestPlanDescriptor(
                path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
                testTargets: [
                    .init(
                        pbxTarget: PBXNativeTarget(name: "AppTests"),
                        containerPath: "container:App.xcodeproj",
                        isEnabled: true,
                        parallelization: .swiftTestingOnly
                    ),
                ],
                language: language,
                region: region
            )
        }

        func defaultOptions(_ plan: TestPlanDescriptor) throws -> [String: Any] {
            let json = try JSONSerialization.jsonObject(with: try plan.encode()) as? [String: Any]
            return try #require(json?["defaultOptions"] as? [String: Any])
        }

        // When
        let pinned = try defaultOptions(descriptor(language: "en", region: "US"))
        let unpinned = try defaultOptions(descriptor(language: nil, region: nil))

        // Then
        #expect(pinned["language"] as? String == "en")
        #expect(pinned["region"] as? String == "US")
        #expect(unpinned.isEmpty)
    }

    @Test func encode_writes_selected_tags() throws {
        // Given
        let descriptor = try Self.descriptor(selectedTags: [".contract"])

        // When
        let testTarget = try Self.firstTestTarget(of: descriptor)

        // Then
        #expect(testTarget["selectedTags"] as? [String: [String]] == ["tags": [".contract"]])
        #expect(testTarget["skippedTags"] == nil)
    }

    @Test func encode_writes_skipped_tags() throws {
        // Given
        let descriptor = try Self.descriptor(skippedTags: [".slow"])

        // When
        let testTarget = try Self.firstTestTarget(of: descriptor)

        // Then
        #expect(testTarget["skippedTags"] as? [String: [String]] == ["tags": [".slow"]])
        #expect(testTarget["selectedTags"] == nil)
    }

    @Test func encode_omits_tag_keys_when_tags_are_empty() throws {
        // Given
        let descriptor = try Self.descriptor()

        // When
        let data = try descriptor.encode()
        let json = try #require(String(data: data, encoding: .utf8))
        let testTarget = try Self.firstTestTarget(of: descriptor)

        // Then
        #expect(!json.contains("selectedTags"))
        #expect(!json.contains("skippedTags"))
        #expect(Set(testTarget.keys) == ["target"])
    }

    private static func descriptor(
        selectedTags: [String] = [],
        skippedTags: [String] = []
    ) throws -> TestPlanDescriptor {
        TestPlanDescriptor(
            path: try AbsolutePath(validating: "/tmp/Plan.xctestplan"),
            testTargets: [
                TestPlanDescriptor.TestTarget(
                    pbxTarget: PBXNativeTarget(name: "AppTests"),
                    containerPath: "container:App.xcodeproj",
                    isEnabled: true,
                    parallelization: .swiftTestingOnly,
                    selectedTags: selectedTags,
                    skippedTags: skippedTags
                ),
            ]
        )
    }

    private static func firstTestTarget(of descriptor: TestPlanDescriptor) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: try descriptor.encode()) as? [String: Any]
        let testTargets = try #require(json?["testTargets"] as? [[String: Any]])
        return try #require(testTargets.first)
    }
}
