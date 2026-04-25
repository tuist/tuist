import FileSystem
import FileSystemTesting
import Foundation
import ProjectDescription
import Testing
import TuistAlert
import TuistTesting
import XcodeGraph

@testable import TuistLoader

struct TestActionManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func action_with_literal_test_plans() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPlanPath = temporaryDirectory.appending(component: "TestPlan.xctestplan")
        try await fileSystem.writeText(testPlanContent, at: testPlanPath)

        let manifest = ProjectDescription.TestAction.testPlans([
            .path(.path(testPlanPath.pathString)),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.count == 1)
        #expect(testAction.testPlans?.first?.path == testPlanPath)
        #expect(testAction.testPlans?.first?.isDefault == true)
    }

    @Test(.inTemporaryDirectory) func action_with_glob_pattern_single_match() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPlanPath = temporaryDirectory.appending(component: "TestPlan.xctestplan")
        try await fileSystem.writeText(testPlanContent, at: testPlanPath)

        let manifest = ProjectDescription.TestAction.testPlans([
            .path("*.xctestplan"),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.count == 1)
        #expect(testAction.testPlans?.first?.path == testPlanPath)
        #expect(testAction.testPlans?.first?.isDefault == true)
    }

    @Test(.inTemporaryDirectory) func action_with_glob_pattern_multiple_matches() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPlan1Path = temporaryDirectory.appending(component: "TestPlan1.xctestplan")
        let testPlan2Path = temporaryDirectory.appending(component: "TestPlan2.xctestplan")

        try await fileSystem.writeText(testPlanContent, at: testPlan1Path)
        try await fileSystem.writeText(testPlanContent, at: testPlan2Path)

        let manifest = ProjectDescription.TestAction.testPlans([
            .path("*.xctestplan"),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.count == 2)
        #expect(testAction.testPlans?.first?.isDefault == true)
        #expect(testAction.testPlans?.last?.isDefault == false)

        let planPaths = testAction.testPlans?.map(\.path).sorted()
        #expect(planPaths == [testPlan1Path, testPlan2Path])
    }

    @Test(.inTemporaryDirectory) func action_with_recursive_glob_pattern() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let subDirectory = temporaryDirectory.appending(component: "TestPlans")
        try await fileSystem.makeDirectory(at: subDirectory)

        let testPlanPath = subDirectory.appending(component: "TestPlan.xctestplan")
        try await fileSystem.writeText(testPlanContent, at: testPlanPath)

        let manifest = ProjectDescription.TestAction.testPlans([
            .path("**/*.xctestplan"),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.count == 1)
        #expect(testAction.testPlans?.first?.path == testPlanPath)
        #expect(testAction.testPlans?.first?.isDefault == true)
    }

    @Test(.inTemporaryDirectory) func action_with_mixed_literal_and_glob_patterns() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let literalPlanPath = temporaryDirectory.appending(component: "LiteralPlan.xctestplan")
        let globPlanPath = temporaryDirectory.appending(component: "GlobPlan.xctestplan")

        try await fileSystem.writeText(testPlanContent, at: literalPlanPath)
        try await fileSystem.writeText(testPlanContent, at: globPlanPath)

        let manifest = ProjectDescription.TestAction.testPlans([
            .path(.path(literalPlanPath.pathString)),
            .path("Glob*.xctestplan"),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.count == 2)
        #expect(testAction.testPlans?.first?.isDefault == true)
        #expect(testAction.testPlans?.last?.isDefault == false)

        let planPaths = testAction.testPlans?.map(\.path)
        #expect(planPaths?.contains(literalPlanPath) == true)
        #expect(planPaths?.contains(globPlanPath) == true)
    }

    @Test(.inTemporaryDirectory) func action_with_glob_pattern_no_matches() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let manifest = ProjectDescription.TestAction.testPlans([
            .path("*.xctestplan"),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans == nil)
    }

    @Test(.inTemporaryDirectory) func action_with_non_xctestplan_files_filtered_out() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testPlanPath = temporaryDirectory.appending(component: "TestPlan.xctestplan")
        let textFilePath = temporaryDirectory.appending(component: "TestPlan.txt")

        try await fileSystem.writeText(testPlanContent, at: testPlanPath)
        try await fileSystem.writeText("test", at: textFilePath)

        let manifest = ProjectDescription.TestAction.testPlans([
            .path("TestPlan.*"),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.count == 1)
        #expect(testAction.testPlans?.first?.path == testPlanPath)
    }

    @Test(.inTemporaryDirectory) func action_with_generated_test_plans_uses_first_as_default() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let manifest = ProjectDescription.TestAction.testPlans([
            .generated(
                name: "UnitTests",
                testTargets: [
                    .testableTarget(target: .project(path: .path(projectPath.pathString), target: "AppTests")),
                ]
            ),
            .generated(
                name: "SnapshotTests",
                testTargets: [
                    .testableTarget(target: .project(path: .path(projectPath.pathString), target: "AppSnapshotTests")),
                ]
            ),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)
        let derivedDirectory = temporaryDirectory.appending(components: "Derived", "TestPlans")

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.count == 2)
        #expect(testAction.testPlans?[0].path == derivedDirectory.appending(component: "UnitTests.xctestplan"))
        #expect(testAction.testPlans?[0].name == "UnitTests")
        #expect(testAction.testPlans?[0].isDefault == true)
        #expect(testAction.testPlans?[0].kind == .generated)
        #expect(testAction.testPlans?[0].testTargets.map(\.target.name) == ["AppTests"])
        #expect(testAction.testPlans?[1].path == derivedDirectory.appending(component: "SnapshotTests.xctestplan"))
        #expect(testAction.testPlans?[1].isDefault == false)
        #expect(testAction.testPlans?[1].kind == .generated)
    }

    @Test(.inTemporaryDirectory) func action_with_generated_test_plan_honors_explicit_path() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let explicitPath = temporaryDirectory.appending(components: "TestPlans", "UnitTests.xctestplan")
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let manifest = ProjectDescription.TestAction.testPlans([
            .generated(
                name: "UnitTests",
                testTargets: [
                    .testableTarget(target: .project(path: .path(projectPath.pathString), target: "AppTests")),
                ],
                path: .path(explicitPath.pathString)
            ),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.first?.path == explicitPath)
        #expect(testAction.testPlans?.first?.kind == .generated)
    }

    @Test(.inTemporaryDirectory) func action_mixes_generated_and_preconfigured_plans() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let preConfiguredPath = temporaryDirectory.appending(component: "Legacy.xctestplan")
        try await fileSystem.writeText(testPlanContent, at: preConfiguredPath)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let manifest = ProjectDescription.TestAction.testPlans([
            .generated(
                name: "UnitTests",
                testTargets: [
                    .testableTarget(target: .project(path: .path(projectPath.pathString), target: "AppTests")),
                ]
            ),
            .path(.path(preConfiguredPath.pathString)),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )

        // Then
        #expect(testAction.testPlans?.count == 2)
        #expect(testAction.testPlans?[0].kind == .generated)
        #expect(testAction.testPlans?[0].isDefault == true)
        #expect(testAction.testPlans?[1].kind == .referenced)
        #expect(testAction.testPlans?[1].path == preConfiguredPath)
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func action_with_literal_test_plan_missing_file_warns() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let missingPlanPath = temporaryDirectory.appending(component: "MissingPlan.xctestplan")
        let schemeName = "MyScheme"

        let manifest = ProjectDescription.TestAction.testPlans([
            .path(.path(missingPlanPath.pathString)),
        ])
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory)

        // When
        let testAction = try await XcodeGraph.TestAction.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            schemeName: schemeName
        )

        // Then
        #expect(testAction.testPlans == nil)
        let warnings = AlertController.current.warnings().map(\.message).map { $0.plain() }
        #expect(
            warnings == [
                "Test plan MissingPlan.xctestplan does not exist at \(missingPlanPath.pathString) referenced by the scheme 'MyScheme'",
            ]
        )
    }
}

private let testPlanContent = """
{
  "configurations" : [
    {
      "id" : "12345678-1234-1234-1234-123456789012",
      "name" : "Configuration 1",
      "options" : {

      }
    }
  ],
  "defaultOptions" : {

  },
  "testTargets" : [

  ],
  "version" : 1
}
"""
