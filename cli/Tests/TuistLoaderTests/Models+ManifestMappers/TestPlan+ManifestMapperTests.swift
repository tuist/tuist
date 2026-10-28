import FileSystem
import FileSystemTesting
import Foundation
import ProjectDescription
import Testing
import XcodeGraph

@testable import TuistLoader

struct TestPlanManifestMapperTests {
    private let fileSystem = FileSystem()

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
        case .path:
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
