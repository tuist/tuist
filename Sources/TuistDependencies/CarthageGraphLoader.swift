import Foundation
import TuistCore
import TSCBasic

public protocol CarthageGraphLoading {
    func load(dependencies: [CarthageDependency], atPath path: AbsolutePath) throws -> DependencyGraph
}

public struct CarthageGraphLoader: CarthageGraphLoading {

    private let otoolController: OtoolControlling
    private let frameworkNodeLoader: FrameworkNodeLoading

    public init(
        otoolController: OtoolControlling = OtoolController(),
        frameworkNodeLoader: FrameworkNodeLoading = FrameworkNodeLoader()
    ) {
        self.otoolController = otoolController
        self.frameworkNodeLoader = frameworkNodeLoader
    }

    public func load(dependencies: [CarthageDependency], atPath path: AbsolutePath) throws -> DependencyGraph {
        DependencyGraph(entryNodes: try dependencies.map { try load(dependency: $0, at: path) })
    }

    private func load(dependency: CarthageDependency, at path: AbsolutePath) throws -> FrameworkNode {
        let frameworkFolderPath = path.appending(RelativePath("\(dependency.name).framework"))
        return try frameworkNodeLoader.load(path: frameworkFolderPath)
    }
}

public struct DependencyGraph {
    /// The entry nodes of the graph.
    public let entryNodes: [FrameworkNode]
}
