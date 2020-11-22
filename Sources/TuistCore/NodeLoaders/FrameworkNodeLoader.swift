import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistSupport

enum FrameworkNodeLoaderError: FatalError, Equatable {
    case frameworkNotFound(AbsolutePath)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .frameworkNotFound:
            return .abort
        }
    }

    /// Error description
    var description: String {
        switch self {
        case let .frameworkNotFound(path):
            return "Couldn't find framework at \(path.pathString)"
        }
    }
}

public protocol FrameworkNodeLoading {
    /// Reads an existing framework and returns its in-memory representation, FrameworkNode.
    /// - Parameter path: Path to the .framework.
    func load(path: AbsolutePath) throws -> FrameworkNode
}

public final class FrameworkNodeLoader: FrameworkNodeLoading {
    /// Framework metadata provider.
    private let frameworkMetadataProvider: FrameworkMetadataProviding

    /// Otool controller.
    private let otoolController: OtoolControlling

    /// Initializes the loader with its attributes.
    /// - Parameter frameworkMetadataProvider: Framework metadata provider.
    public init(frameworkMetadataProvider: FrameworkMetadataProviding = FrameworkMetadataProvider(),
                otoolController: OtoolControlling = OtoolController())
    {
        self.frameworkMetadataProvider = frameworkMetadataProvider
        self.otoolController = otoolController
    }

    public func load(path: AbsolutePath) throws -> FrameworkNode {
        guard FileHandler.shared.exists(path) else {
            throw FrameworkNodeLoaderError.frameworkNotFound(path)
        }

        let binaryPath = FrameworkNode.binaryPath(frameworkPath: path)
        let dsymsPath = frameworkMetadataProvider.dsymPath(frameworkPath: path)
        let bcsymbolmapPaths = try frameworkMetadataProvider.bcsymbolmapPaths(frameworkPath: path)
        let linking = try frameworkMetadataProvider.linking(binaryPath: binaryPath)
        let architectures = try frameworkMetadataProvider.architectures(binaryPath: binaryPath)

        let dependencies = try dlybDependenciesPath(forBinaryAt: binaryPath)

        return FrameworkNode(path: path,
                             dsymPath: dsymsPath,
                             bcsymbolmapPaths: bcsymbolmapPaths,
                             linking: linking,
                             architectures: architectures,
                             dependencies: dependencies)
    }

    private func dlybDependenciesPath(forBinaryAt binaryPath: AbsolutePath) throws -> [PrecompiledNode.Dependency] {
        try otoolController
            .dlybDependenciesPath(forBinaryAt: binaryPath)
            .toBlocking()
            .first()?
            .filter { $0 != binaryPath }
            .map { $0.removingLastComponent() }
            .map { dependencyPath -> PrecompiledNode.Dependency in
                let node = try load(path: dependencyPath)
                return PrecompiledNode.Dependency.framework(node)
            } ?? []
    }
}
