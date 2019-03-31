import Basic
import Foundation
@testable import TuistGenerator

final class MockGraphLoaderCache: GraphLoaderCaching {
    var projects: [AbsolutePath: Project] = [:]
    var targetNodes: [AbsolutePath: [String: TargetNode]] = [:]
    var precompiledNodes: [AbsolutePath: PrecompiledNode] = [:]
    var projectStub: ((AbsolutePath) -> Project?)?
    var projectCount: UInt = 0
    var addProjectCount: UInt = 0
    var addProjectArgs: [Project] = []
    var addConfigCount: UInt = 0
    var addPrecompiledNodeCount: UInt = 0
    var addPrecompiledArgs: [PrecompiledNode] = []
    var precompiledNodeCount: UInt = 0
    var precompiledNodeStub: ((AbsolutePath) -> PrecompiledNode?)?
    var addTargetNodeCount: UInt = 0
    var addTargetNodeArgs: [TargetNode] = []
    var targetNodeCount: UInt = 0
    var targetNodeStub: ((AbsolutePath, String) -> TargetNode?)?

    func project(_ path: AbsolutePath) -> Project? {
        projectCount += 1
        return projectStub?(path)
    }

    func add(project: Project) {
        addProjectCount += 1
        addProjectArgs.append(project)
    }

    func add(precompiledNode: PrecompiledNode) {
        addPrecompiledNodeCount += 1
        addPrecompiledArgs.append(precompiledNode)
    }

    func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode? {
        precompiledNodeCount += 1
        return precompiledNodeStub?(path)
    }

    func add(targetNode: TargetNode) {
        addTargetNodeCount += 1
        addTargetNodeArgs.append(targetNode)
    }

    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode? {
        targetNodeCount += 1
        return targetNodeStub?(path, name)
    }
}
