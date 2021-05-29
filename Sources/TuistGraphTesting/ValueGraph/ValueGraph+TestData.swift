import Foundation
import TSCBasic
import TuistGraph

public extension ValueGraph {
    static func test(name: String = "graph",
                     path: AbsolutePath = .root,
                     workspace: Workspace = .test(),
                     projects: [AbsolutePath: Project] = [:],
                     packages: [AbsolutePath: [String: Package]] = [:],
                     targets: [AbsolutePath: [String: Target]] = [:],
                     dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [:]) -> ValueGraph
    {
        ValueGraph(
            name: name,
            path: path,
            workspace: workspace,
            projects: projects,
            packages: packages,
            targets: targets,
            dependencies: dependencies
        )
    }
}
