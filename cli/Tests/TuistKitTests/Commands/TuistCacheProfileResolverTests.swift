import Foundation
import Testing
import TuistConfig
import TuistCore

@testable import TuistKit

struct TuistCacheProfileResolverTests {
    @Test func explicit_cache_profile_overrides_target_focus() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: ["App"],
            cacheProfile: CacheProfileType.none
        )

        // Then
        #expect(result == .none)
    }

    @Test func target_focus_implies_allPossible_when_no_explicit_cache_profile() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: ["App"],
            cacheProfile: nil
        )

        // Then
        #expect(result == .allPossible)
    }

    @Test func explicit_onlyExternal_overrides_target_focus() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: ["App"],
            cacheProfile: CacheProfileType.onlyExternal
        )

        // Then
        #expect(result == .onlyExternal)
    }

    @Test func resolves_from_explicit_builtins() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When / Then
        #expect(try config
            .resolveCacheProfile(ignoreBinaryCache: false, includedTargets: [], cacheProfile: .onlyExternal) == .onlyExternal
        )
        #expect(try config
            .resolveCacheProfile(ignoreBinaryCache: false, includedTargets: [], cacheProfile: .allPossible) == .allPossible
        )
        #expect(try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: [],
            cacheProfile: CacheProfileType.none
        ) == .none)
    }

    @Test func resolves_from_explicit_custom_profile() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "development": .init(base: .onlyExternal, targetQueries: ["tag:expensive"]),
                    ],
                    default: .onlyExternal
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: [],
            cacheProfile: "development"
        )

        // Then
        #expect(result == .init(base: .onlyExternal, targetQueries: ["tag:expensive"]))
    }

    @Test func resolves_from_config_default_builtin() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [:],
                    default: .allPossible
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: [],
            cacheProfile: nil
        )

        // Then
        #expect(result == .allPossible)
    }

    @Test func resolves_from_config_default_custom() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "ci": .init(base: .onlyExternal, targetQueries: ["tag:cacheable"]),
                    ],
                    default: "ci"
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: [],
            cacheProfile: nil
        )

        // Then
        #expect(result == .init(base: .onlyExternal, targetQueries: ["tag:cacheable"]))
    }

    @Test func resolves_command_default_custom_from_config_default_for_test_context() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "ci": .init(
                            base: .commandDefault,
                            targetQueries: ["tag:cacheable"],
                            exceptTargetQueries: ["tag:no-cache"]
                        ),
                    ],
                    default: "ci"
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: [],
            cacheProfile: nil,
            commandDefault: .allPossible
        )

        // Then
        #expect(result == .init(
            base: .allPossible,
            targetQueries: ["tag:cacheable"],
            exceptTargetQueries: ["tag:no-cache"]
        ))
    }

    @Test func resolves_command_default_custom_from_config_default_for_focused_generate() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "ci": .init(
                            base: .commandDefault,
                            targetQueries: ["tag:cacheable"],
                            exceptTargetQueries: ["tag:no-cache"]
                        ),
                    ],
                    default: "ci"
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: ["App"],
            cacheProfile: nil
        )

        // Then
        #expect(result == .init(
            base: .allPossible,
            targetQueries: ["tag:cacheable"],
            exceptTargetQueries: ["tag:no-cache"]
        ))
    }

    @Test func resolves_explicit_command_default_custom_against_resolved_config_default() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "ci": .init(
                            base: .commandDefault,
                            targetQueries: ["tag:cacheable"]
                        ),
                        "firestore-workaround": .init(
                            base: .commandDefault,
                            exceptTargetQueries: ["FirebaseFirestore"]
                        ),
                    ],
                    default: "ci"
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: ["App"],
            cacheProfile: "firestore-workaround"
        )

        // Then
        #expect(result == .init(
            base: .allPossible,
            targetQueries: ["tag:cacheable"],
            exceptTargetQueries: ["FirebaseFirestore"]
        ))
    }

    @Test func context_falls_back_to_all_possible_when_no_explicit_and_no_config_default() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: [],
            cacheProfile: nil,
            commandDefault: .allPossible
        )

        // Then
        #expect(result == .allPossible)
    }

    @Test func throws_when_custom_profile_missing() {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When / Then
        #expect(throws: CacheProfileError.profileNotFound(profile: "missing", available: [])) {
            _ = try config.resolveCacheProfile(
                ignoreBinaryCache: false,
                includedTargets: [],
                cacheProfile: "missing"
            )
        }
    }

    @Test func none_overrides_focus_and_explicit() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())
        let included: Set<TargetQuery> = ["App"]

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: true,
            includedTargets: included,
            cacheProfile: .allPossible
        )

        // Then
        #expect(result == .none)
    }

    @Test func ignore_binary_cache_overrides_command_default_custom_profiles() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "ci": .init(
                            base: .commandDefault,
                            targetQueries: ["tag:cacheable"],
                            exceptTargetQueries: ["tag:no-cache"]
                        ),
                    ],
                    default: "ci"
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: true,
            includedTargets: ["App"],
            cacheProfile: "ci",
            commandDefault: .allPossible
        )

        // Then
        #expect(result == .none)
    }

    @Test func falls_back_to_onlyExternal_when_no_explicit_and_no_config_default() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When
        let result = try config.resolveCacheProfile(
            ignoreBinaryCache: false,
            includedTargets: [],
            cacheProfile: nil
        )

        // Then
        #expect(result == .onlyExternal)
    }

    @Test func throws_when_config_default_custom_missing() {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [:],
                    default: .allPossible
                )
            )))
        )

        // When / Then
        #expect(throws: CacheProfileError.profileNotFound(profile: "missing", available: [])) {
            _ = try config.resolveCacheProfile(
                ignoreBinaryCache: false,
                includedTargets: [],
                cacheProfile: "missing"
            )
        }
    }
}
