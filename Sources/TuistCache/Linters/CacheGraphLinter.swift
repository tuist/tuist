import Foundation
import TuistCore
import TuistSupport

/// Protocol that defines the interface to lint a graph and warn
/// the user if the projects have traits that are not caching-compliant.
public protocol CacheGraphLinting {
    /// Lint a given graph.
    /// - Parameter graph: Graph to be linted.
    func lint(graph: Graph)
}

public final class CacheGraphLinter: CacheGraphLinting {
    public init() {}

    public func lint(graph: Graph) {
        let targets = graph.targets.flatMap(\.value)
        let targetsWithActions = targets.filter { $0.target.actions.count != 0 }
        if !targetsWithActions.isEmpty {
            let message: Logger.Message = """
            The following targets contain actions that might introduce non-cacheable side-effects: \(targetsWithActions.map(\.name).joined(separator: ", ")).
            Note that a side-effect is an action that given an input (e.g. Xcode build variable) it affects the target built products.
            If it's not your case, it's safe to ignore this warning. Otherwise, you can bring up your use case on the comunity forum, \(Constants.communityURL), to explore adding a cache-compliant interface for your use-case.
            """
            logger.warning(message)
        }
    }
}
