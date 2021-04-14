import Foundation
import TuistCache
import TuistCore
import TuistGraph

public final class MockCacheGraphLinter: CacheGraphLinting {
    public var invokedLint = false
    public var invokedLintCount = 0
    public var invokedLintParameters: (graph: ValueGraph, Void)?
    public var invokedLintParametersList = [(graph: ValueGraph, Void)]()

    public init() {}

    public func lint(graph: ValueGraph) {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graph, ())
        invokedLintParametersList.append((graph, ()))
    }
}
