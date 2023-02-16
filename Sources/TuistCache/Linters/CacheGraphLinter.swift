import Foundation
import TuistCore
import TuistGraph
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
        let graphTraverser = GraphTraverser(graph: graph)
        let targets = graphTraverser.allTargets()
        let targetsWithScripts = targets.filter { $0.target.scripts.count != 0 }
        if !targetsWithScripts.isEmpty {
            let message: Logger.Message = """
            The following targets contain scripts that might introduce non-cacheable side-effects: \(targetsWithScripts
                .map(\.target.name).joined(separator: ", ")).
            Note that a side-effect is an action that affects the target built products based on a given input (e.g. Xcode build variable).
            These warnings can be ignored when the scripts do not have side effects. Please report eventual use cases to the community forum \(Constants
                .communityURL).
            """
            logger.warning(message)
        }
    }
}
