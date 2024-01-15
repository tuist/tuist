import Foundation
import TSCBasic
import TuistCore
import TuistGraph
@testable import TuistKit

final class MockGeneratorFactory: GeneratorFactorying {
    var invokedTest = false
    var invokedTestCount = 0
    var invokedTestParameters: (
        config: Config,
        testsCacheDirectory: AbsolutePath,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool
    )?
    var invokedTestParametersList =
        [(
            config: Config,
            testsCacheDirectory: AbsolutePath,
            testPlan: String?,
            includedTargets: Set<String>,
            excludedTargets: Set<String>,
            skipUITests: Bool
        )]()
    var stubbedTestResult: Generating!

    func test(
        config: Config,
        testsCacheDirectory: AbsolutePath,
        testPlan: String?,
        includedTargets: Set<String>,
        excludedTargets: Set<String>,
        skipUITests: Bool
    ) -> Generating {
        invokedTest = true
        invokedTestCount += 1
        invokedTestParameters = (
            config,
            testsCacheDirectory,
            testPlan,
            includedTargets,
            excludedTargets,
            skipUITests
        )
        invokedTestParametersList
            .append((
                config,
                testsCacheDirectory,
                testPlan,
                includedTargets,
                excludedTargets,
                skipUITests
            ))
        return stubbedTestResult
    }

    var invokedDefault = false
    var invokedDefaultCount = 0
    var stubbedDefaultResult: Generating!

    func `default`(config _: Config) -> Generating {
        invokedDefault = true
        invokedDefaultCount += 1
        return stubbedDefaultResult
    }
}
