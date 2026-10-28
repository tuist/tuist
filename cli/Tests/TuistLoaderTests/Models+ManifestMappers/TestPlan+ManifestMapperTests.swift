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
            fileSystem: fileSystem
        )

        // Then
        #expect(got.map(\.language) == ["en"])
        #expect(got.map(\.region) == ["US"])
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
