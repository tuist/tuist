import Foundation
import TSCBasic

@testable import TuistCore

public extension TargetNode {
    static func test(project: Project = .test(),
                     target: Target = .test(),
                     dependencies: [GraphNode] = [],
                     prune: Bool = false) -> TargetNode
    {
        TargetNode(project: project,
                   target: target,
                   dependencies: dependencies,
                   prune: prune)
    }
}
