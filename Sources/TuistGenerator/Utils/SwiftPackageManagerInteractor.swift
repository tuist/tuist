import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

/// Swift Package Manager Interactor
///
/// This component is responsible for resolving
/// any Swift package manager dependencies declared
/// within projects in the graph.
///
public protocol SwiftPackageManagerInteracting {
    /// Installs Swift Package dependencies for a given graph and workspace
    ///
    /// - The installation process involves performing a Swift package dependency
    /// resolution to generated the `Package.resolved` file (via `xcodebuild`).
    /// - This file is then symlinked to the root path of the workspace.
    ///
    /// - Note: this should be called post generation and writing projects
    ///         and workspaces to disk.
    ///
    /// - Parameters:
    ///   - graphTraverser: The graph traverser.
    ///   - workspaceName: The name GraphTraversing the generated workspace (e.g. `MyWorkspace.xcworkspace`)
    func install(graphTraverser: GraphTraversing, workspaceName: String, config: Config) async throws
}

public class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    private let fileHandler: FileHandling
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func install(graphTraverser: GraphTraversing, workspaceName: String, config: Config = .default) async throws {
        try await generatePackageDependencyManager(
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
    ) async throws {
        guard !config.generationOptions.disablePackageVersionLocking,
              graphTraverser.hasRemotePackages
        else {
            return
        }

        let rootPackageResolvedPath = path.appending(component: ".package.resolved")
        let workspacePackageResolvedFolderPath = path
            .appending(try RelativePath(validating: "\(workspaceName)/xcshareddata/swiftpm"))
        let workspacePackageResolvedPath = workspacePackageResolvedFolderPath.appending(component: "Package.resolved")

        if fileHandler.exists(rootPackageResolvedPath), !fileHandler.exists(workspacePackageResolvedPath) {
            if !fileHandler.exists(workspacePackageResolvedPath.parentDirectory) {
                try fileHandler.createFolder(workspacePackageResolvedPath.parentDirectory)
            }
            try fileHandler.linkFile(atPath: rootPackageResolvedPath, toPath: workspacePackageResolvedPath)
        }

        let workspacePath = path.appending(component: workspaceName)
        logger.notice("Resolving package dependencies using xcodebuild")
        // -list parameter is a workaround to resolve package dependencies for given workspace without specifying scheme
        var arguments = ["xcodebuild", "-resolvePackageDependencies"]

        // This allows using the system-defined git credentials instead of using Xcode's accounts permissions
        if config.generationOptions.resolveDependenciesWithSystemScm {
            arguments.append(contentsOf: ["-scmProvider", "system"])
        }

        // Set specific clone directory for Xcode managed SPM dependencies
        if let clonedSourcePackagesDirPath = config.generationOptions.clonedSourcePackagesDirPath {
            let workspace = (workspaceName as NSString).deletingPathExtension
            let path = "\(clonedSourcePackagesDirPath.pathString)/\(workspace)"
            arguments.append(contentsOf: ["-clonedSourcePackagesDirPath", path])
        }

        arguments.append(contentsOf: ["-workspace", workspacePath.pathString, "-list"])

        try System.shared.run(
            arguments,
            verbose: false,
            environment: System.shared.env,
            redirection: .stream(stdout: { bytes in
                let output = String(decoding: bytes, as: Unicode.UTF8.self)
                logger.debug("\(output)")
            }, stderr: { bytes in
                let error = String(decoding: bytes, as: Unicode.UTF8.self)
                logger.error("\(error)")
            })
        )

        if !fileHandler.exists(rootPackageResolvedPath), fileHandler.exists(workspacePackageResolvedPath) {
            try fileHandler.copy(from: workspacePackageResolvedPath, to: rootPackageResolvedPath)
            if !fileHandler.exists(workspacePackageResolvedPath) {
                try fileHandler.linkFile(atPath: rootPackageResolvedPath, toPath: workspacePackageResolvedPath)
            }
        }
    }
}
