import Basic
import Foundation
@testable import TuistGenerator

final class MockGraphLoaderCache: GraphLoaderCaching {
    var projects: [AbsolutePath: Project] = [:]
    var targetNodes: [AbsolutePath: [String: TargetNode]] = [:]
    var precompiledNodes: [AbsolutePath: PrecompiledNode] = [:]
    var projectStub: ((AbsolutePath) -> Project?)?
    var projectCount: UInt = 0
    var addProjectArgs: [Project] = []
    var addConfigCount: UInt = 0
    var addPrecompiledNodeCount: UInt = 0
    var addPrecompiledArgs: [PrecompiledNode] = []
    var precompiledNodeCount: UInt = 0
    var precompiledNodeStub: ((AbsolutePath) -> PrecompiledNode?)?
    var addTargetNodeArgs: [TargetNode] = []
    var targetNodeStub: ((AbsolutePath, String) -> TargetNode?)?
    var tuistConfigStub: [AbsolutePath: TuistConfig] = [:]
    var addTuistConfigArgs: [(tuistConfig: TuistConfig, path: AbsolutePath)] = []
    var cocoaPodsNodes: [AbsolutePath: CocoaPodsNode] = [:]
    var cocoapodsStub: [AbsolutePath: CocoaPodsNode] = [:]
    var addCococaPodsArgs: [CocoaPodsNode] = []

    func cocoapods(_ path: AbsolutePath) -> CocoaPodsNode? {
        return cocoapodsStub[path]
    }

    func add(cocoaPods: CocoaPodsNode) {
        addCococaPodsArgs.append(cocoaPods)
    }

    func tuistConfig(_ path: AbsolutePath) -> TuistConfig? {
        return tuistConfigStub[path]
    }

    func add(tuistConfig: TuistConfig, path: AbsolutePath) {
        addTuistConfigArgs.append((tuistConfig: tuistConfig, path: path))
    }

    func project(_ path: AbsolutePath) -> Project? {
        projectCount += 1
        return projectStub?(path)
    }

    func add(project: Project) {
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
        addTargetNodeArgs.append(targetNode)
    }

    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode? {
        return targetNodeStub?(path, name)
    }
}
