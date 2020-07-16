import Foundation
import RxBlocking
import TSCBasic
import TuistCore
import TuistSupport

enum SwiftPackageManagerInteractorError: FatalError, Equatable {
    case rootDirectoryNotFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .rootDirectoryNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .rootDirectoryNotFound(path):
            return "Couldn't locate the root directory from path \(path.pathString). The root directory is the closest directory that contains a Tuist or a .git directory."
        }
    }
}

/// Swift Package Manager Interactor
///
/// This component is responsible for resolving
/// any Swift package manager dependencies declared
/// within projects in the graph.
///
public protocol SwiftPackageManagerInteracting {
    /// Installs Swift Package dependencies for a given graph and workspace
    ///
    /// - The instllation process involves performing a Swift package dependency
    /// resolution to generated the `Package.resolved` file (via `xcodebuild`).
    /// - This file is then symlinked to the root path of the workspace.
    ///
    /// - Note: this should be called post generation and writing projects
    ///         and workspaces to disk.
    ///
    /// - Parameters:
    ///   - graph: The graph of projects
    ///   - workspaceName: The name of the generated workspace (e.g. `MyWorkspace.xcworkspace`)
    func install(graph: Graph, workspaceName: String) throws
}

public class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    private let fileHandler: FileHandling
    private let rootDirectoryLocator: RootDirectoryLocating
    public init(
        fileHandler: FileHandling = FileHandler.shared,
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.fileHandler = fileHandler
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func install(graph: Graph, workspaceName: String) throws {
        try generatePackageDependencyManager(at: graph.entryPath,
                                             workspaceName: workspaceName,
                                             graph: graph)
    }

    private func generatePackageDependencyManager(
        at path: AbsolutePath,
        workspaceName: String,
        graph: Graph
    ) throws {
        let packages = graph.packages.compactMap { $0 }
        guard !packages.remotePackages.isEmpty else {
            return
        }

        guard let rootDirectory = rootDirectoryLocator.locate(from: path) else { throw SwiftPackageManagerInteractorError.rootDirectoryNotFound(path) }
        let rootPackageResolvedPath = rootDirectory.appending(component: ".package.resolved")
        let workspacePackageResolvedFolderPath = path.appending(RelativePath("\(workspaceName)/xcshareddata/swiftpm"))
        let workspacePackageResolvedPath = workspacePackageResolvedFolderPath.appending(component: "Package.resolved")

        if fileHandler.exists(rootPackageResolvedPath) {
            try fileHandler.createFolder(workspacePackageResolvedFolderPath)
            if fileHandler.exists(workspacePackageResolvedPath) {
                try fileHandler.delete(workspacePackageResolvedPath)
            }
            try fileHandler.copy(from: rootPackageResolvedPath, to: workspacePackageResolvedPath)
        }

        let workspacePath = path.appending(component: workspaceName)
        logger.notice("Resolving package dependencies using xcodebuild")
        // -list parameter is a workaround to resolve package dependencies for given workspace without specifying scheme
        _ = try System.shared.observable(["xcodebuild", "-resolvePackageDependencies", "-workspace", workspacePath.pathString, "-list"])
            .mapToString()
            .do(onNext: { event in
                switch event {
                case let .standardError(error):
                    logger.error("\(error)")
                case let .standardOutput(output):
                    logger.debug("\(output)")
                }
            })
            .toBlocking()
            .last()

        if fileHandler.exists(rootPackageResolvedPath) {
            try fileHandler.delete(rootPackageResolvedPath)
        }

        try fileHandler.linkFile(atPath: workspacePackageResolvedPath, toPath: rootPackageResolvedPath)
    }
}

private extension Array where Element == PackageNode {
    var remotePackages: [PackageNode] {
        compactMap { node in
            switch node.package {
            case .remote:
                return node
            default:
                return nil
            }
        }
    }
}
