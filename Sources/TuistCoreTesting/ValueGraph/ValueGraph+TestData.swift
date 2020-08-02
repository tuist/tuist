import Foundation
import TSCBasic
import TuistCore

public extension ValueGraph {
    static func test(name: String = "graph",
                     path: AbsolutePath,
                     projects: [AbsolutePath: Project] = [:],
                     packages: [AbsolutePath: [String: Package]] = [:],
                     targets: [AbsolutePath: [String: Target]] = [:],
                     dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [:]) -> ValueGraph
    {
        ValueGraph(name: name,
                   path: path,
                   projects: projects,
                   packages: packages,
                   targets: targets,
                   dependencies: dependencies)
    }
}
