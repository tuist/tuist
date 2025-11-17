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
        let got = try TuistCore.CacheOptions.from(manifest: manifest)
        #expect(got.keepSourceTargets == true)
    }

    @Test func from_mapsKeepSourceTargets_false() throws {
        let manifest = ProjectDescription.Config.CacheOptions.options(keepSourceTargets: false)
        let got = try TuistCore.CacheOptions.from(manifest: manifest)
        #expect(got.keepSourceTargets == false)
    }

    @Test func additionalPackageResolutionArguments_includes_resolveDependenciesWithSystemScm() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // When
            let got = try TuistCore.TuistGeneratedProjectOptions.GenerationOptions.from(
                manifest: .options(
                    resolveDependenciesWithSystemScm: true
                ),
                generatorPaths: GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory),
                fullHandle: nil
            )

            // Then
            #expect(got.additionalPackageResolutionArguments == ["-scmProvider", "system"])
        }
    }

    @Test func additionalPackageResolutionArguments_without_deprecated_flags() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // When
            let got = try TuistCore.TuistGeneratedProjectOptions.GenerationOptions.from(
                manifest: .options(
                    additionalPackageResolutionArguments: ["-verbose", "-configuration", "debug"]
                ),
                generatorPaths: GeneratorPaths(manifestDirectory: temporaryDirectory, rootDirectory: temporaryDirectory),
                fullHandle: nil
            )

            // Then
            #expect(got.additionalPackageResolutionArguments == ["-verbose", "-configuration", "debug"])
            #expect(!got.additionalPackageResolutionArguments.contains("-resolvePackageDependenciesWithSystemScm"))
        }
    }

    @Test func from_mapsEmptyCacheProfiles_with_default_onlyExternal() throws {
        // When
        let got = TuistCore.CacheProfiles.from(
            manifest: .profiles(
                [:],
                default: .onlyExternal
            )
        )

        // Then
        #expect(got.profileByName == [:])
        #expect(got.defaultProfile == .onlyExternal)
    }

    @Test func from_mapsCacheProfiles_entries_and_custom_default() throws {
        // When
        let got = TuistCore.CacheProfiles.from(
            manifest: .profiles(
                [
                    "development": .profile(
                        .allPossible,
                        and: ["Expensive", .tagged("cacheable")]
                    ),
                    "ci": .profile(
                        .onlyExternal,
                        and: []
                    ),
                ],
                default: "development"
            )
        )

        // Then
        #expect(got.profileByName == [
            "development": .init(
                base: .allPossible,
                targetQueries: ["Expensive", "tag:cacheable"]
            ),
            "ci": .init(
                base: .onlyExternal,
                targetQueries: []
            ),
        ])
        #expect(got.defaultProfile == "development")
    }

    @Test func from_mapsCacheOptions_profiles() throws {
        // When
        let got = try TuistCore.CacheOptions.from(
            manifest: .options(
                keepSourceTargets: false,
                profiles: .profiles(
                    [
                        "debug": .profile(
                            .onlyExternal,
                            and: [.tagged("stable")]
                        ),
                    ],
                    default: "debug"
                )
            )
        )

        // Then
        #expect(got.profiles.profileByName == [
            "debug": .init(
                base: .onlyExternal,
                targetQueries: ["tag:stable"]
            ),
        ])
        #expect(got.profiles.defaultProfile == "debug")
    }

    @Test func from_throws_whenCustomProfileNameIsReserved() throws {
        for reservedName in BaseCacheProfile.allCases.map(\.rawValue) {
            #expect(throws: CacheOptionsManifestMapperError.reservedProfileName(profile: reservedName)) {
                _ = try TuistCore.CacheOptions.from(
                    manifest: .options(
                        keepSourceTargets: false,
                        profiles: .profiles(
                            [
                                reservedName: .profile(.onlyExternal, and: []),
                            ],
                            default: .onlyExternal
                        )
                    )
                )
            }
        }
    }
}
