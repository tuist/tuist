import FileSystem
import FileSystemTesting
import Foundation
import ProjectDescription
import Testing
import TuistConfig
import TuistCore

@testable import TuistLoader

struct TuistGeneratedProjectManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory, arguments: [(false, false), (true, false), (false, true), (true, true)])
    func generationOptions_mapsCoverage(enabled: Bool, prefixMapping: Bool) throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let options = ProjectDescription.Config.GenerationOptions.options(
            enableCaching: true,
            coverage: .coverage(enabled: enabled, prefixMapping: prefixMapping)
        )
        let manifest = try JSONDecoder().decode(
            ProjectDescription.Config.GenerationOptions.self,
            from: JSONEncoder().encode(options)
        )
        #expect(manifest == options)
        let got = try TuistConfig.TuistGeneratedProjectOptions.GenerationOptions.from(
            manifest: manifest,
            generatorPaths: GeneratorPaths(manifestDirectory: directory, rootDirectory: directory),
            fullHandle: nil
        )

        #expect(got.coverage == .init(enabled: enabled, prefixMapping: prefixMapping))
    }

    @Test func generationOptions_coverageIsOffByDefault() {
        let options = ProjectDescription.Config.GenerationOptions.options(enableCaching: true)

        #expect(options.coverage == .coverage())
        #expect(options.coverage.enabled == false)
        #expect(options.coverage.prefixMapping == false)
    }

    /// A manifest encoded before `coverage` existed has no such key; it decodes with coverage off.
    @Test func generationOptions_decodesAMissingCoverageKeyAsOff() throws {
        let options = ProjectDescription.Config.GenerationOptions.options(
            enableCaching: true,
            coverage: .coverage(enabled: true, prefixMapping: true)
        )
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any]
        )
        json.removeValue(forKey: "coverage")

        let got = try JSONDecoder().decode(
            ProjectDescription.Config.GenerationOptions.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        #expect(got.coverage == .coverage())
        #expect(got.enableCaching == true)
    }

    /// The overload without `coverage` keeps its pre-`coverage` signature, so typed references to it still compile.
    @Test func generationOptions_factoryWithoutCoverageKeepsItsSignature() {
        let factory: (
            Bool, ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets, String?, Bool, Bool, Bool,
            Bool, Bool, Bool, Bool, [String], ProjectDescription.Config.GenerationOptions.WarningsAsErrors, String,
            [String], ProjectDescription.Config.GenerationOptions.OutdatedDependenciesAction,
            ProjectDescription.Config.GenerationOptions.ProjectFormat
        ) -> ProjectDescription.Config.GenerationOptions = ProjectDescription.Config.GenerationOptions.options

        let got = factory(false, .all, nil, false, false, false, true, true, true, false, [], .none, "5", [], .warn, .pbxproj)

        #expect(got.enableCaching == true)
        #expect(got.coverage == .coverage())
    }

    @Test func installOptions_mapsManifestEnvironment() {
        let got = TuistConfig.TuistGeneratedProjectOptions.InstallOptions.from(
            manifest: .options(
                passthroughSwiftPackageManagerArguments: ["--force-resolved-versions"],
                packageManifestEnvironment: .automatic(
                    including: ["CI_JOB_ID"],
                    excluding: ["GITHUB_RUN_*"]
                )
            )
        )

        #expect(got.passthroughSwiftPackageManagerArguments == ["--force-resolved-versions"])
        #expect(got.packageManifestEnvironment.usesAutomaticProviderDefaults == true)
        #expect(got.packageManifestEnvironment.includedVariablePatterns == ["CI_JOB_ID"])
        #expect(got.packageManifestEnvironment.excludedVariablePatterns == ["GITHUB_RUN_*"])
    }

    @Test func buildInsightsDisabled_when_fullHandle_is_nil() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // When
            let got = try TuistConfig.TuistGeneratedProjectOptions.GenerationOptions.from(
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
            let got = try TuistConfig.TuistGeneratedProjectOptions.GenerationOptions.from(
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
            let got = try TuistConfig.TuistGeneratedProjectOptions.GenerationOptions.from(
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
        let got = try TuistConfig.CacheOptions.from(manifest: manifest)
        #expect(got.keepSourceTargets == true)
    }

    @Test func from_mapsKeepSourceTargets_false() throws {
        let manifest = ProjectDescription.Config.CacheOptions.options(keepSourceTargets: false)
        let got = try TuistConfig.CacheOptions.from(manifest: manifest)
        #expect(got.keepSourceTargets == false)
    }

    @Test func additionalPackageResolutionArguments_includes_resolveDependenciesWithSystemScm() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // When
            let got = try TuistConfig.TuistGeneratedProjectOptions.GenerationOptions.from(
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
            let got = try TuistConfig.TuistGeneratedProjectOptions.GenerationOptions.from(
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
        let got = TuistConfig.CacheProfiles.from(
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
        let got = TuistConfig.CacheProfiles.from(
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
        let got = try TuistConfig.CacheOptions.from(
            manifest: .options(
                keepSourceTargets: false,
                profiles: .profiles(
                    [
                        "debug": .profile(
                            .onlyExternal,
                            and: [.tagged("stable")],
                            except: ["Excluded", .tagged("no-cache")]
                        ),
                        "simple": .profile(
                            .allPossible,
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
                targetQueries: ["tag:stable"],
                exceptTargetQueries: ["Excluded", "tag:no-cache"]
            ),
            "simple": .init(
                base: .allPossible,
                targetQueries: ["tag:stable"]
            ),
        ])
        #expect(got.profiles.defaultProfile == "debug")
    }

    @Test func from_mapsStorages_default() throws {
        let manifest = ProjectDescription.Config.CacheOptions.options()
        let got = try TuistConfig.CacheOptions.from(manifest: manifest)
        #expect(got.storages == [.local, .remote])
    }

    @Test func from_mapsStorages_localOnly() throws {
        let manifest = ProjectDescription.Config.CacheOptions.options(storages: [.local])
        let got = try TuistConfig.CacheOptions.from(manifest: manifest)
        #expect(got.storages == [.local])
    }

    @Test func from_mapsStorages_remoteOnly() throws {
        let manifest = ProjectDescription.Config.CacheOptions.options(storages: [.remote])
        let got = try TuistConfig.CacheOptions.from(manifest: manifest)
        #expect(got.storages == [.remote])
    }

    @Test func from_throws_whenCustomProfileNameIsReserved() throws {
        for reservedName in BaseCacheProfile.allCases.map(\.rawValue) {
            #expect(throws: CacheOptionsManifestMapperError.reservedProfileName(profile: reservedName)) {
                _ = try TuistConfig.CacheOptions.from(
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
