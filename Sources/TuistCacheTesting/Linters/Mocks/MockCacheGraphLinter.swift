import Foundation
import TuistCache
import TuistCore

public final class MockCacheGraphLinter: CacheGraphLinting {
    public var invokedLint = false
    public var invokedLintCount = 0
    public var invokedLintParameters: (graph: Graph, Void)?
    public var invokedLintParametersList = [(graph: Graph, Void)]()

    public init() {}

    public func lint(graph: Graph) {
        invokedLint = true
        invokedLintCount += 1
        invokedLintParameters = (graph, ())
        invokedLintParametersList.append((graph, ()))
    }
}
