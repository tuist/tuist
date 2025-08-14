import FileSystem
import Foundation
import ProjectDescription
import Testing
import TuistCore

@testable import TuistLoader

struct TuistGeneratedProjectManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test func buildInsightsDisabled_when_fullHandle_is_nil() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // When
            let got = try TuistCore.TuistGeneratedProjectOptions.GenerationOptions.from(
                manifest: .options(),
                generatorPaths: GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory),
                fullHandle: nil
            )

            // Then
            #expect(got.buildInsightsDisabled == true)
        }
    }

    @Test func buildInsightsDisabled_when_fullHandle_is_defined() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // When
            let got = try TuistCore.TuistGeneratedProjectOptions.GenerationOptions.from(
                manifest: .options(),
                generatorPaths: GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory),
                fullHandle: "tuist/tuist"
            )

            // Then
            #expect(got.buildInsightsDisabled == false)
        }
    }

    @Test func buildInsightsDisabled_when_fullHandle_is_defined_and_insights_disabled_in_generation_options() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // When
            let got = try TuistCore.TuistGeneratedProjectOptions.GenerationOptions.from(
                manifest: .options(
                    buildInsightsDisabled: true
                ),
                generatorPaths: GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory),
                fullHandle: "tuist/tuist"
            )

            // Then
            #expect(got.buildInsightsDisabled == true)
        }
    }

    @Test func from_mapsKeepSourceTargets_true() throws {
        let manifest = ProjectDescription.Config.CacheOptions.options(keepSourceTargets: true)
        let got = TuistCore.TuistGeneratedProjectOptions.CacheOptions.from(manifest: manifest)
        #expect(got.keepSourceTargets == true)
    }

    @Test func from_mapsKeepSourceTargets_false() throws {
        let manifest = ProjectDescription.Config.CacheOptions.options(keepSourceTargets: false)
        let got = TuistCore.TuistGeneratedProjectOptions.CacheOptions.from(manifest: manifest)
        #expect(got.keepSourceTargets == false)
    }
}
