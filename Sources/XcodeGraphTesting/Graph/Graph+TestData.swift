import Foundation
import Path
import XcodeGraph

extension Graph {
    public static func test(
        name: String = "graph",
        path: AbsolutePath = .root,
        workspace: Workspace = .test(),
        projects: [AbsolutePath: Project] = [:],
        packages: [AbsolutePath: [String: Package]] = [:],
        dependencies: [GraphDependency: Set<GraphDependency>] = [:],
        dependencyConditions: [GraphEdge: PlatformCondition] = [:]
    ) -> Graph {
        Graph(
            name: name,
            path: path,
            workspace: workspace,
            projects: projects,
            packages: packages,
            dependencies: dependencies,
            dependencyConditions: dependencyConditions
        )
    }
}
