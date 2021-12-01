import Foundation
import TSCBasic
import TuistGraph

extension Graph {
    public static func test(
        name: String = "graph",
        path: AbsolutePath = .root,
        workspace: Workspace = .test(),
        projects: [AbsolutePath: Project] = [:],
        packages: [AbsolutePath: [String: Package]] = [:],
        targets: [AbsolutePath: [String: Target]] = [:],
        dependencies: [GraphDependency: Set<GraphDependency>] = [:]
    ) -> Graph {
        Graph(
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
