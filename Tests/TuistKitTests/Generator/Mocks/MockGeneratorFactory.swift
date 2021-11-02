import Foundation
import TuistGraph
import TuistCore
import TSCBasic
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
        ignoreCache: Bool) -> Generating {
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
    var stubbedDefaultResult: Generating!

    func `default`() -> Generating {
        invokedDefault = true
        invokedDefaultCount += 1
        return stubbedDefaultResult
    }

}
