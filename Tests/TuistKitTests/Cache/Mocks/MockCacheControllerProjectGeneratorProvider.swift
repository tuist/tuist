import Foundation
import TuistGraph
@testable import TuistKit

final class MockCacheControllerProjectGeneratorProvider: CacheControllerProjectGeneratorProviding {
    var invokedGenerator = false
    var invokedGeneratorCount = 0
    var stubbedGeneratorResult: Generating!
    var invokedGeneratorTargetsToFilter = false
    var invokedGeneratorTargetsToFilterCount = 0
    var stubbedGeneratorTargetsToFilterResult: Generating!

    func generator() -> Generating {
        invokedGenerator = true
        invokedGeneratorCount += 1
        return stubbedGeneratorResult
    }

    func generator(includedTargets _: [Target]) -> Generating {
        invokedGeneratorTargetsToFilter = true
        invokedGeneratorTargetsToFilterCount += 1
        return stubbedGeneratorTargetsToFilterResult
    }
}
