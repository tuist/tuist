import Foundation
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

        let folderPath = path.removingLastComponent()

        let dependencies: [PrecompiledNode.Dependency] = try otoolController
            .dlybDependenciesPath(forBinaryAt: binaryPath)
            .filter { $0.contains("@rpath") }
            .map { String($0.dropFirst(7)) } // dropping @rpath/
            .compactMap { (dependencyPath: String) in
                let name = String(dependencyPath.split(separator: "/").first ?? "")
                guard !path.pathString.contains(name) else { return nil }

                let tPath = folderPath.appending(RelativePath("\(name)"))
                guard let node = try? load(path: tPath) else { return nil }

                return PrecompiledNode.Dependency.framework(node)
            }

        return FrameworkNode(path: path,
                             dsymPath: dsymsPath,
                             bcsymbolmapPaths: bcsymbolmapPaths,
                             linking: linking,
                             architectures: architectures,
                             dependencies: dependencies)
    }
}
