import Foundation
import RxBlocking
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

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
    ///   - graph: The graph traverser.
    ///   - workspaceName: The name GraphTraversing the generated workspace (e.g. `MyWorkspace.xcworkspace`)
    func install(graphTraverser: GraphTraversing, workspaceName: String, config: Config) throws
}

public class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    private let fileHandler: FileHandling
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func install(graphTraverser: GraphTraversing, workspaceName: String, config: Config = .default) throws {
        try generatePackageDependencyManager(
            at: graphTraverser.path,
            workspaceName: workspaceName,
            config: config,
            graphTraverser: graphTraverser
        )
    }

    private func generatePackageDependencyManager(
        at path: AbsolutePath,
        workspaceName: String,
        config: Config,
        graphTraverser: GraphTraversing
    ) throws {
        guard !config.generationOptions.contains(.disablePackageVersionLocking),
            graphTraverser.hasRemotePackages
        else {
            return
        }

        let rootPackageResolvedPath = path.appending(component: ".package.resolved")
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
        var arguments = ["xcodebuild", "-resolvePackageDependencies"]

        // This allows using the system-defined git credentials instead of using Xcode's accounts permissions
        if config.generationOptions.contains(.resolveDependenciesWithSystemScm) {
            arguments.append(contentsOf: ["-scmProvider", "system"])
        }

        arguments.append(contentsOf: ["-workspace", workspacePath.pathString, "-list"])

        _ = try System.shared.observable(arguments)
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
