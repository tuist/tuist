import FileSystem
import FileSystemTesting
import Foundation
import ProjectDescription
import Testing
import XcodeGraph

@testable import TuistLoader

struct TestableTargetManifestMapperTests {
    @Test(.inTemporaryDirectory) func maps_selected_and_skipped_tags() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectDescription.TestableTarget.testableTarget(
            target: "AppTests",
            selectedTags: [".contract"],
            skippedTags: [".slow", ".flaky"]
        )

        // When
        let got = try XcodeGraph.TestableTarget.from(
            manifest: manifest,
            generatorPaths: GeneratorPaths(
                manifestDirectory: temporaryDirectory,
                rootDirectory: temporaryDirectory
            )
        )

        // Then
        #expect(got.selectedTags == [".contract"])
        #expect(got.skippedTags == [".slow", ".flaky"])
    }

    @Test(.inTemporaryDirectory) func prepends_a_dot_to_an_undotted_tag() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectDescription.TestableTarget.testableTarget(
            target: "AppTests",
            selectedTags: ["contract"],
            skippedTags: ["slow"]
        )

        // When
        let got = try XcodeGraph.TestableTarget.from(
            manifest: manifest,
            generatorPaths: GeneratorPaths(
                manifestDirectory: temporaryDirectory,
                rootDirectory: temporaryDirectory
            )
        )

        // Then
        #expect(got.selectedTags == [".contract"])
        #expect(got.skippedTags == [".slow"])
    }

    @Test(.inTemporaryDirectory) func leaves_an_already_dotted_tag_unchanged() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectDescription.TestableTarget.testableTarget(
            target: "AppTests",
            selectedTags: [".contract"]
        )

        // When
        let got = try XcodeGraph.TestableTarget.from(
            manifest: manifest,
            generatorPaths: GeneratorPaths(
                manifestDirectory: temporaryDirectory,
                rootDirectory: temporaryDirectory
            )
        )

        // Then
        #expect(got.selectedTags == [".contract"])
    }

    @Test(.inTemporaryDirectory) func leaves_a_qualified_tag_unchanged() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectDescription.TestableTarget.testableTarget(
            target: "AppTests",
            selectedTags: ["Tag.contract"]
        )

        // When
        let got = try XcodeGraph.TestableTarget.from(
            manifest: manifest,
            generatorPaths: GeneratorPaths(
                manifestDirectory: temporaryDirectory,
                rootDirectory: temporaryDirectory
            )
        )

        // Then
        #expect(got.selectedTags == ["Tag.contract"])
    }

    @Test(.inTemporaryDirectory) func trims_whitespace_and_drops_empty_tags() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectDescription.TestableTarget.testableTarget(
            target: "AppTests",
            selectedTags: [" contract ", "", "   "],
            skippedTags: ["  ", " .slow "]
        )

        // When
        let got = try XcodeGraph.TestableTarget.from(
            manifest: manifest,
            generatorPaths: GeneratorPaths(
                manifestDirectory: temporaryDirectory,
                rootDirectory: temporaryDirectory
            )
        )

        // Then
        #expect(got.selectedTags == [".contract"])
        #expect(got.skippedTags == [".slow"])
    }

    @Test(.inTemporaryDirectory) func defaults_to_empty_tag_arrays() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let manifest = ProjectDescription.TestableTarget.testableTarget(target: "AppTests")

        // When
        let got = try XcodeGraph.TestableTarget.from(
            manifest: manifest,
            generatorPaths: GeneratorPaths(
                manifestDirectory: temporaryDirectory,
                rootDirectory: temporaryDirectory
            )
        )

        // Then
        #expect(got.selectedTags.isEmpty)
        #expect(got.skippedTags.isEmpty)
    }
}
