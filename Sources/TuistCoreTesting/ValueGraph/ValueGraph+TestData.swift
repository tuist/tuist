import Foundation
import TSCBasic
import TuistCore

public extension ValueGraph {
    static func test(projects: [AbsolutePath: Project] = [:],
                     packages: [AbsolutePath: [String: Package]] = [:],
                     targets: [AbsolutePath: [String: Target]] = [:],
                     dependencies: [ValueGraphDependency: [ValueGraphDependency]] = [:]) -> ValueGraph {
        ValueGraph(projects: projects,
                   packages: packages,
                   targets: targets,
                   dependencies: dependencies)
    }
}
