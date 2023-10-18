import Foundation
import TSCBasic
import TuistCore
import TuistGraph
@testable import TuistKit

final class MockGeneratorFactory: GeneratorFactorying {
    var invokedFocus = false
    var invokedFocusCount = 0
    var invokedFocusParameters: (
        config: Config,
        sources: Set<String>,
        cacheOutputType: CacheOutputType,
        cacheProfile: TuistGraph.Cache.Profile,
        ignoreCache: Bool,
        targetsToSkipCache: Set<String>
    )?
    var invokedFocusParametersList =
        [(
            config: Config,
            sources: Set<String>,
            cacheOutputType: CacheOutputType,
            cacheProfile: TuistGraph.Cache.Profile,
            ignoreCache: Bool
        )]()
    var stubbedFocusResult: Generating!

    func focus(
        config: Config,
        sources: Set<String>,
        cacheOutputType: CacheOutputType,
        cacheProfile: TuistGraph.Cache.Profile,
        ignoreCache: Bool,
        targetsToSkipCache: Set<String>
    ) -> Generating {
        invokedFocus = true
        invokedFocusCount += 1
        invokedFocusParameters = (config, sources, cacheOutputType, cacheProfile, ignoreCache, targetsToSkipCache)
        invokedFocusParametersList.append((config, sources, cacheOutputType, cacheProfile, ignoreCache))
        return stubbedFocusResult
    }

    var invokedTest = false
    var invokedTestCount = 0
    var invokedTestParameters: (
        config: Config,
        testsCacheDirectory: AbsolutePath,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool,
        cacheOutputType: TuistCore.CacheOutputType,
        cacheProfile: TuistGraph.Cache.Profile,
        ignoreCache: Bool,
        targetsToSkipCache: Set<String>
    )?
    var invokedTestParametersList =
        [(
            config: Config,
            testsCacheDirectory: AbsolutePath,
            testPlan: String?,
            includedTargets: Set<String>,
            excludedTargets: Set<String>,
            skipUITests: Bool,
            cacheOutputType: TuistCore.CacheOutputType,
            cacheProfile: TuistGraph.Cache.Profile,
            ignoreCache: Bool,
            targetsToSkipCache: Set<String>
        )]()
    var stubbedTestResult: Generating!

    func test(
        config: Config,
        testsCacheDirectory: AbsolutePath,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool,
        cacheOutputType: TuistCore.CacheOutputType,
        cacheProfile: TuistGraph.Cache.Profile,
        ignoreCache: Bool,
        targetsToSkipCache: Set<String>
    ) -> Generating {
        invokedTest = true
        invokedTestCount += 1
        invokedTestParameters = (
            config,
            testsCacheDirectory,
            testPlan,
            includedTargets,
            excludedTargets,
            skipUITests,
            cacheOutputType,
            cacheProfile,
            ignoreCache,
            targetsToSkipCache
        )
        invokedTestParametersList
            .append((
                config,
                testsCacheDirectory,
                testPlan,
                includedTargets,
                excludedTargets,
                skipUITests,
                cacheOutputType,
                cacheProfile,
                ignoreCache,
                targetsToSkipCache
            ))
        return stubbedTestResult
    }

    var invokedDefault = false
    var invokedDefaultCount = 0
    var stubbedDefaultResult: Generating!

    func `default`() -> Generating {
        invokedDefault = true
        invokedDefaultCount += 1
        return stubbedDefaultResult
    }

    var invokedCache = false
    var invokedCacheCount = 0
    var invokedCacheParameters: (
        config: Config,
        includedTargets: Set<String>,
        focusedTargets: Set<String>?,
        cacheOutputType: CacheOutputType,
        cacheProfile: Cache.Profile
    )?
    var invokedCacheParametersList = [(
        config: Config,
        includedTargets: Set<String>,
        focusedTargets: Set<String>?,
        cacheOutputType: CacheOutputType,
        cacheProfile: Cache.Profile
    )]()
    var stubbedCacheResult: Generating!

    func cache(
        config: Config,
        includedTargets: Set<String>,
        focusedTargets: Set<String>?,
        cacheOutputType: CacheOutputType,
        cacheProfile: Cache.Profile
    ) -> Generating {
        invokedCache = true
        invokedCacheCount += 1
        invokedCacheParameters = (config, includedTargets, focusedTargets, cacheOutputType, cacheProfile)
        invokedCacheParametersList.append((config, includedTargets, focusedTargets, cacheOutputType, cacheProfile))
        return stubbedCacheResult
    }
}
