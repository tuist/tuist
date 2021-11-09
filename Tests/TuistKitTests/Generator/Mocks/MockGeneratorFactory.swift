import Foundation
import TSCBasic
import TuistCore
import TuistGraph
@testable import TuistKit

final class MockGeneratorFactory: GeneratorFactorying {
    var invokedFocus = false
    var invokedFocusCount = 0
    var invokedFocusParameters: (config: Config, sources: Set<String>, xcframeworks: Bool, cacheProfile: TuistGraph.Cache.Profile, ignoreCache: Bool)?
    var invokedFocusParametersList = [(config: Config, sources: Set<String>, xcframeworks: Bool, cacheProfile: TuistGraph.Cache.Profile, ignoreCache: Bool)]()
    var stubbedFocusResult: Generating!

    func focus(config: Config,
               sources: Set<String>,
               xcframeworks: Bool,
               cacheProfile: TuistGraph.Cache.Profile,
               ignoreCache: Bool) -> Generating
    {
        invokedFocus = true
        invokedFocusCount += 1
        invokedFocusParameters = (config, sources, xcframeworks, cacheProfile, ignoreCache)
        invokedFocusParametersList.append((config, sources, xcframeworks, cacheProfile, ignoreCache))
        return stubbedFocusResult
    }

    var invokedTest = false
    var invokedTestCount = 0
    var invokedTestParameters: (config: Config, automationPath: AbsolutePath, testsCacheDirectory: AbsolutePath, skipUITests: Bool)?
    var invokedTestParametersList = [(config: Config, automationPath: AbsolutePath, testsCacheDirectory: AbsolutePath, skipUITests: Bool)]()
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
    var invokedDefaultParameters: (config: Config, Void)?
    var invokedDefaultParametersList = [(config: Config, Void)]()
    var stubbedDefaultResult: Generating!

    func `default`(config: Config) -> Generating {
        invokedDefault = true
        invokedDefaultCount += 1
        invokedDefaultParameters = (config, ())
        invokedDefaultParametersList.append((config, ()))
        return stubbedDefaultResult
    }

    var invokedCache = false
    var invokedCacheCount = 0
    var invokedCacheParameters: (config: Config, includedTargets: Set<String>?)?
    var invokedCacheParametersList = [(config: Config, includedTargets: Set<String>?)]()
    var stubbedCacheResult: Generating!

    func cache(config: Config, includedTargets: Set<String>?) -> Generating {
        invokedCache = true
        invokedCacheCount += 1
        invokedCacheParameters = (config, includedTargets)
        invokedCacheParametersList.append((config, includedTargets))
        return stubbedCacheResult
    }
}
