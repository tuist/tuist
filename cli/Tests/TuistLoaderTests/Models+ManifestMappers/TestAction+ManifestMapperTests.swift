import FileSystem
import FileSystemTesting
import Foundation
import ProjectDescription
import Testing
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
            .path(testPlanPath.pathString),
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
            .path(literalPlanPath.pathString),
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
        #expect(testAction.testPlans?.isEmpty == true)
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
