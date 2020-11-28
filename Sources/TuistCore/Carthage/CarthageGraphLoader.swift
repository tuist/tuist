import Foundation
import TSCBasic
import TuistSupport

public enum CarthageGraphLoaderError: FatalError, Equatable {
    case invalidPath(AbsolutePath)

    /// Error type.
    public var type: ErrorType {
        switch self {
        case .invalidPath:
            return .abort
        }
    }

    /// Error description
    public var description: String {
        switch self {
        case let .invalidPath(path):
            return "The path: \(path) is not a valid Carthage path."
        }
    }
}

public protocol CarthageGraphLoading {
    /// Loads the given dependencies at the given path.
    /// - Parameter dependencies: Array of dependencies to be fetched with carthage
    /// - Parameter path: Path to the platform directory inside Carthage Build folder.
    /// - Returns DependencyGraph with transitive dependencies
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
        guard path.pathString.contains("Carthage/Build") else {
            throw CarthageGraphLoaderError.invalidPath(path)
        }
        return DependencyGraph(entryNodes: try dependencies.map { try load(dependency: $0, at: path) })
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
