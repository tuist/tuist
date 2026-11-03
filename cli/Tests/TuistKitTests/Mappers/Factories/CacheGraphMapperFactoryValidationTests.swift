import Testing
import TuistConfig
import TuistServer
import XcodeGraph
@testable import TuistCore
@testable import TuistKit
@testable import TuistTesting

#if canImport(TuistCacheEE)
    import TuistCacheEE

    struct CacheGraphMapperFactoryValidationTests {
        private let cacheStorage = MockCacheStoring()
        private let subject = CacheGraphMapperFactory(contentHasher: ContentHasher())

        @Test func generation_validates_the_requested_targets_when_source_targets_are_kept() {
            // Given
            let config = Tuist.test(project: .generated(.test(cacheOptions: .test(keepSourceTargets: true))))
            let cacheSources: Set<TargetQuery> = [.named("MyTarget")]

            // When
            let got = subject.generation(
                config: config,
                cacheProfile: .allPossible,
                cacheSources: cacheSources,
                configuration: "Debug",
                cacheStorage: cacheStorage
            )

            // Then
            let mapper = got.compactMap { $0 as? ValidateIncludedTargetsGraphMapper }.first
            #expect(mapper?.includedTargets == cacheSources)
        }

        @Test func generation_validates_the_requested_targets_when_the_binary_cache_is_disabled() {
            // Given
            let config = Tuist.test(project: .generated(.test(cacheOptions: .test(keepSourceTargets: true))))
            let cacheSources: Set<TargetQuery> = [.named("MyTarget")]

            // When
            let got = subject.generation(
                config: config,
                cacheProfile: .none,
                cacheSources: cacheSources,
                configuration: "Debug",
                cacheStorage: cacheStorage
            )

            // Then
            let mapper = got.compactMap { $0 as? ValidateIncludedTargetsGraphMapper }.first
            #expect(mapper?.includedTargets == cacheSources)
        }

        @Test func generation_leaves_the_validation_to_the_focus_mapper_when_the_graph_is_focused() {
            // Given
            let config = Tuist.test(project: .generated(.test(cacheOptions: .test(keepSourceTargets: false))))

            // When
            let got = subject.generation(
                config: config,
                cacheProfile: .allPossible,
                cacheSources: [.named("MyTarget")],
                configuration: "Debug",
                cacheStorage: cacheStorage
            )

            // Then
            #expect(got.contains { $0 is FocusTargetsGraphMappers })
            #expect(!got.contains { $0 is ValidateIncludedTargetsGraphMapper })
        }

        @Test func generation_does_not_validate_when_no_targets_were_requested() {
            // Given
            let config = Tuist.test(project: .generated(.test(cacheOptions: .test(keepSourceTargets: true))))

            // When
            let got = subject.generation(
                config: config,
                cacheProfile: .allPossible,
                cacheSources: [],
                configuration: "Debug",
                cacheStorage: cacheStorage
            )

            // Then
            #expect(!got.contains { $0 is ValidateIncludedTargetsGraphMapper })
        }
    }
#endif
