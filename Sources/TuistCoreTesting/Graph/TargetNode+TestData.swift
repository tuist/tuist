import Foundation
import TSCBasic
import TuistGraph
@testable import TuistCore

public extension TargetNode {
    static func test(project: Project = .test(),
                     target: Target = .test(),
                     dependencies: [GraphNode] = []) -> TargetNode
    {
        TargetNode(project: project,
                   target: target,
                   dependencies: dependencies)
    }
}
