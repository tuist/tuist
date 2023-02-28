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
        ignoreCache: Bool
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
        ignoreCache: Bool
    ) -> Generating {
        invokedFocus = true
        invokedFocusCount += 1
        invokedFocusParameters = (config, sources, cacheOutputType, cacheProfile, ignoreCache)
        invokedFocusParametersList.append((config, sources, cacheOutputType, cacheProfile, ignoreCache))
        return stubbedFocusResult
    }

    var invokedTest = false
    var invokedTestCount = 0
    var invokedTestParameters: (
        config: Config,
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool
    )?
    var invokedTestParametersList =
        [(config: Config, automationPath: AbsolutePath, testsCacheDirectory: AbsolutePath, skipUITests: Bool)]()
    var stubbedTestResult: Generating!

    func test(
        config: Config,
        automationPath: AbsolutePath,
        testsCacheDirectory: AbsolutePath,
        skipUITests: Bool
    ) -> Generating {
        invokedTest = true
        invokedTestCount += 1
        invokedTestParameters = (config, automationPath, testsCacheDirectory, skipUITests)
        invokedTestParametersList.append((config, automationPath, testsCacheDirectory, skipUITests))
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
