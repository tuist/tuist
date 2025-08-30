import Foundation
import Testing
import TuistCore

@testable import TuistKit

struct TuistCacheProfileResolverTests {
    @Test func resolves_allPossible_when_targets_focused_even_if_explicit_set() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When
        let result = try config.resolveCacheProfile(
            binaryCache: true,
            includedTargets: ["App"],
            explicitCacheProfile: "none"
        )

        // Then
        #expect(result == .init(base: .allPossible, targets: []))
    }

    @Test func resolves_from_explicit_builtins() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When / Then
        #expect(try config.resolveCacheProfile(binaryCache: true, includedTargets: [], explicitCacheProfile: "only-external") == .init(base: .onlyExternal, targets: []))
        #expect(try config.resolveCacheProfile(binaryCache: true, includedTargets: [], explicitCacheProfile: "all-possible") == .init(base: .allPossible, targets: []))
        #expect(try config.resolveCacheProfile(binaryCache: true, includedTargets: [], explicitCacheProfile: "none") == .init(base: .none, targets: []))
    }

    @Test func resolves_from_explicit_custom_profile() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "development": .init(base: .onlyExternal, targets: ["tag:expensive"]),
                    ],
                    default: .onlyExternal
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            binaryCache: true,
            includedTargets: [],
            explicitCacheProfile: "development"
        )

        // Then
        #expect(result == .init(base: .onlyExternal, targets: ["tag:expensive"]))
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
            binaryCache: true,
            includedTargets: [],
            explicitCacheProfile: nil
        )

        // Then
        #expect(result == .init(base: .allPossible, targets: []))
    }

    @Test func resolves_from_config_default_custom() throws {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [
                        "ci": .init(base: .onlyExternal, targets: ["tag:cacheable"]),
                    ],
                    default: .custom("ci")
                )
            )))
        )

        // When
        let result = try config.resolveCacheProfile(
            binaryCache: true,
            includedTargets: [],
            explicitCacheProfile: nil
        )

        // Then
        #expect(result == .init(base: .onlyExternal, targets: ["tag:cacheable"]))
    }

    @Test func throws_when_custom_profile_missing() {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When / Then
        #expect(throws: CacheProfileError.profileNotFound("missing")) {
            _ = try config.resolveCacheProfile(
                binaryCache: true,
                includedTargets: [],
                explicitCacheProfile: "missing"
            )
        }
    }

    @Test func none_overrides_focus_and_explicit() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())
        let included: Set<TargetQuery> = ["App"]

        // When
        let result = try config.resolveCacheProfile(
            binaryCache: false,
            includedTargets: included,
            explicitCacheProfile: "all-possible"
        )

        // Then
        #expect(result == .init(base: .none, targets: []))
    }

    @Test func falls_back_to_onlyExternal_when_no_explicit_and_no_config_default() throws {
        // Given
        let config = Tuist.test(project: .testGeneratedProject())

        // When
        let result = try config.resolveCacheProfile(
            binaryCache: true,
            includedTargets: [],
            explicitCacheProfile: nil
        )

        // Then
        #expect(result == .init(base: .onlyExternal, targets: []))
    }

    @Test func throws_when_config_default_custom_missing() {
        // Given
        let config = Tuist.test(project:
            .generated(.test(cacheOptions: .test(
                keepSourceTargets: false,
                profiles: .init(
                    [:],
                    default: .custom("missing")
                )
            )))
        )

        // When / Then
        #expect(throws: CacheProfileError.profileNotFound("missing")) {
            _ = try config.resolveCacheProfile(
                binaryCache: true,
                includedTargets: [],
                explicitCacheProfile: nil
            )
        }
    }
}
