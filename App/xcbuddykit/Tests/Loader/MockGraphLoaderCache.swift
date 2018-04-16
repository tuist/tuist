import Foundation
import PathKit
@testable import xcbuddykit

final class MockGraphLoaderCache: GraphLoaderCaching {
    var projectStub: ((Path) -> Project?)?
    var projectCount: UInt = 0
    var addProjectCount: UInt = 0
    var addProjectArgs: [Project] = []
    var addConfigCount: UInt = 0
    var addConfigArgs: [Config] = []
    var configStub: ((Path) -> Config?)?
    var configCount: UInt = 0
    var addNodeCount: UInt = 0
    var addNodeArgs: [GraphNode] = []
    var nodeCount: UInt = 0
    var nodeStub: ((Path) -> GraphNode?)?

    func project(_ path: Path) -> Project? {
        projectCount += 1
        return projectStub?(path)
    }

    func config(_ path: Path) -> Config? {
        configCount += 1
        return configStub?(path)
    }

    func add(project: Project) {
        addProjectCount += 1
        addProjectArgs.append(project)
    }

    func add(config: Config) {
        addConfigCount += 1
        addConfigArgs.append(config)
    }

    func add(node: GraphNode) {
        addNodeCount += 1
        addNodeArgs.append(node)
    }

    func node(_ path: Path) -> GraphNode? {
        nodeCount += 1
        return nodeStub?(path)
    }
}
