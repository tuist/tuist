import Foundation
@testable import TuistKit

final class MockCacheControllerProjectGeneratorProvider: CacheControllerProjectGeneratorProviding {
    var invokedGenerator = false
    var invokedGeneratorCount = 0
    var stubbedGeneratorResult: ProjectGenerating!

    func generator() -> ProjectGenerating {
        invokedGenerator = true
        invokedGeneratorCount += 1
        return stubbedGeneratorResult
    }
}
