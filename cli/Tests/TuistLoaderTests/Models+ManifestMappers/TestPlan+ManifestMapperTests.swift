import FileSystem
import FileSystemTesting
import Foundation
import ProjectDescription
import Testing
import XcodeGraph

@testable import TuistLoader

struct TestPlanManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test func generated_preserves_the_legacy_constructor_pattern_and_json() throws {
        let factory: (String, [ProjectDescription.TestableTarget], ProjectDescription.Path?) -> ProjectDescription.TestPlan =
            ProjectDescription.TestPlan.generated
        let plan = factory("UnitTests", [], "Plans/UnitTests.xctestplan")

        guard case let .generated(name, targets, path) = plan else {
            Issue.record("The legacy constructor must produce the original generated case")
            return
        }
        #expect(name == "UnitTests")
        #expect(targets.isEmpty)
        #expect(path == "Plans/UnitTests.xctestplan")

        let historical = Data(
            """
            {"generated":{"name":"UnitTests","testTargets":[],"path":{
              "type":"relativeToManifest","pathString":"Plans/UnitTests.xctestplan"
            }}}
            """.utf8
        )
        #expect(try JSONDecoder().decode(ProjectDescription.TestPlan.self, from: historical) == plan)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: historical) as? NSDictionary
        #expect(encoded == expected)
    }

    @Test func generated_with_nil_locale_preserves_the_legacy_representation() {
        let plan = ProjectDescription.TestPlan.generated(name: "UnitTests", testTargets: [], language: nil, region: nil)

        #expect(plan == .generated(name: "UnitTests", testTargets: []))
    }

    @Test(.inTemporaryDirectory) func plan_when_manifest_directory_is_in_a_subdirectory() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPlanPath = temporaryDirectory.appending(component: "TestPlan.xctestplan")
        let manifestDirectory = temporaryDirectory.appending(component: "App")
        try await fileSystem.writeText(
            """
            {
              "testTargets" : [
                {
                  "target" : {
                    "containerPath" : "container:App.xcodeproj",
                    "identifier" : "99DCC7BD0ABB09C467644299",
                    "name" : "AppTests"
                  }
                }
              ]
            }
            """,
            at: testPlanPath
        )

        // When
        let got = try await TestPlan.from(
            path: testPlanPath,
            isDefault: false,
            generatorPaths: GeneratorPaths(
                manifestDirectory: manifestDirectory,
                rootDirectory: temporaryDirectory
            )
        )

        // Then
        #expect(
            got == TestPlan(
                path: testPlanPath,
                testTargets: [
                    TestableTarget(
                        target: TargetReference(
                            projectPath: manifestDirectory,
                            name: "AppTests"
                        )
                    ),
                ],
                isDefault: false
            )
        )
    }

    @Test(.inTemporaryDirectory) func generated_plan_maps_language_and_region() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectDescription.TestPlan.generated(
            name: "UnitTests",
            testTargets: [.testableTarget(target: "AppTests")],
            language: "en",
            region: "US"
        )

        // When
        let got = try await TestPlan.from(
            manifests: [manifest],
            generatorPaths: GeneratorPaths(
                manifestDirectory: temporaryDirectory,
                rootDirectory: temporaryDirectory
            ),
            schemeName: nil,
            fileSystem: fileSystem,
            generatedOptions: .options(coverage: true, codeCoverageTargets: ["App"])
        )

        // Then
        #expect(got.map(\.language) == ["en"])
        #expect(got.map(\.region) == ["US"])
        #expect(got.map(\.coverage) == [true])
        #expect(got.first?.codeCoverageTargets == [TargetReference(projectPath: temporaryDirectory, name: "App")])
    }

    @Test(.inTemporaryDirectory) func plan_with_bare_container_path_resolves_to_manifest_directory() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPlanPath = temporaryDirectory.appending(component: "TestPlan.xctestplan")
        let manifestDirectory = temporaryDirectory.appending(component: "App")
        try await fileSystem.writeText(
            """
            {
              "testTargets" : [
                {
                  "target" : {
                    "containerPath" : "container:",
                    "identifier" : "AppTests",
                    "name" : "AppTests"
                  }
                }
              ]
            }
            """,
            at: testPlanPath
        )

        // When
        let got = try await TestPlan.from(
            path: testPlanPath,
            isDefault: false,
            generatorPaths: GeneratorPaths(
                manifestDirectory: manifestDirectory,
                rootDirectory: temporaryDirectory
            )
        )

        // Then
        #expect(
            got == TestPlan(
                path: testPlanPath,
                testTargets: [
                    TestableTarget(
                        target: TargetReference(
                            projectPath: manifestDirectory,
                            name: "AppTests"
                        )
                    ),
                ],
                isDefault: false
            )
        )
    }
}

struct GeneratedTestPlanCompatibilityTests {
    @Test func legacy_patterns_factories_and_json_are_preserved() throws {
        let factory: (String, [ProjectDescription.TestableTarget], ProjectDescription.Path?) -> ProjectDescription.TestPlan =
            ProjectDescription.TestPlan.generated
        let plan = factory("Legacy", [], nil)
        switch plan {
        case .path, .generatedWithLocale:
            Issue.record("Expected the generated case")
        case let .generated(name, targets, path):
            #expect(name == "Legacy")
            #expect(targets.isEmpty)
            #expect(path == nil)
        }
        let oldPayload = Data(#"{"generated":{"name":"Legacy","testTargets":[]}}"#.utf8)
        #expect(try JSONDecoder().decode(ProjectDescription.TestPlan.self, from: oldPayload) == plan)

        let inferredFactory = ProjectDescription.TestAction.testPlans
        let actionFactory: (
            [ProjectDescription.TestPlan], ProjectDescription.ConfigurationName, Bool,
            [ProjectDescription.ExecutionAction], [ProjectDescription.ExecutionAction]
        ) -> ProjectDescription.TestAction = inferredFactory
        let action = actionFactory([plan], .debug, true, [], [])
        #expect(action.generatedTestPlanOptions == nil)
        let data = try JSONEncoder().encode(action)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["generatedTestPlanOptions"] == nil)
        #expect(try JSONDecoder().decode(ProjectDescription.TestAction.self, from: data) == action)
    }
}
