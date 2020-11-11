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
            Note that a side-effect is an action that affects the target built products based on a given input (e.g. Xcode build variable).
            These warnings can be ignored when the actions do not have side effects. Please report eventual use cases to the community forum \(Constants.communityURL).
            """
            logger.warning(message)
        }
    }
}
