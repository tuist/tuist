import Basic
import Foundation
@testable import TuistCore

public final class MockGraphLoaderCache: GraphLoaderCaching {
    public var projects: [AbsolutePath: Project] = [:]
    public var targetNodes: [AbsolutePath: [String: TargetNode]] = [:]
    public var precompiledNodes: [AbsolutePath: PrecompiledNode] = [:]
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
    public var cocoapodsNodes: [AbsolutePath: CocoaPodsNode] = [:]
    var cocoapodsStub: [AbsolutePath: CocoaPodsNode] = [:]
    var addCococaPodsArgs: [CocoaPodsNode] = []
    public var packageNodes: [AbsolutePath: PackageProductNode] = [:]
    var packagesStub: [AbsolutePath: PackageProductNode] = [:]
    var addPackageArgs: [PackageProductNode] = []
    public var packages: [AbsolutePath: [PackageNode]] = [:]

    public func package(_ path: AbsolutePath) -> PackageProductNode? {
        return packagesStub[path]
    }

    public func add(package: PackageProductNode) {
        addPackageArgs.append(package)
    }

    public func cocoapods(_ path: AbsolutePath) -> CocoaPodsNode? {
        return cocoapodsStub[path]
    }

    public func add(cocoapods: CocoaPodsNode) {
        addCococaPodsArgs.append(cocoapods)
    }

    public func tuistConfig(_ path: AbsolutePath) -> TuistConfig? {
        return tuistConfigStub[path]
    }

    public func add(tuistConfig: TuistConfig, path: AbsolutePath) {
        addTuistConfigArgs.append((tuistConfig: tuistConfig, path: path))
    }

    public func project(_ path: AbsolutePath) -> Project? {
        projectCount += 1
        return projectStub?(path)
    }

    public func add(project: Project) {
        addProjectArgs.append(project)
    }

    public func add(precompiledNode: PrecompiledNode) {
        addPrecompiledNodeCount += 1
        addPrecompiledArgs.append(precompiledNode)
    }

    public func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode? {
        precompiledNodeCount += 1
        return precompiledNodeStub?(path)
    }

    public func add(targetNode: TargetNode) {
        addTargetNodeArgs.append(targetNode)
    }

    public func targetNode(_ path: AbsolutePath, name: String) -> TargetNode? {
        return targetNodeStub?(path, name)
    }
}
