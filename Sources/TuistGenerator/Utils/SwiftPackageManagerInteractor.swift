import FileSystem
import Foundation
import Path
import ServiceContextModule
import TuistCore
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
    private let fileSystem: FileSysteming
    private let system: Systeming
    public init(
        fileSystem: FileSysteming = FileSystem(),
        system: Systeming = System.shared
    ) {
        self.fileSystem = fileSystem
        self.system = system
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
              graphTraverser.hasPackages
        else {
            return
        }

        let rootPackageResolvedPath = path.appending(component: ".package.resolved")
        let workspacePackageResolvedFolderPath = path
            .appending(try RelativePath(validating: "\(workspaceName)/xcshareddata/swiftpm"))
        let workspacePackageResolvedPath = workspacePackageResolvedFolderPath.appending(component: "Package.resolved")

        if try await fileSystem.exists(rootPackageResolvedPath), try await !fileSystem.exists(workspacePackageResolvedPath) {
            if try await !fileSystem.exists(workspacePackageResolvedPath.parentDirectory) {
                try await fileSystem.makeDirectory(at: workspacePackageResolvedPath.parentDirectory)
            }
            try await fileSystem.createSymbolicLink(from: workspacePackageResolvedPath, to: rootPackageResolvedPath)
        }

        let workspacePath = path.appending(component: workspaceName)
        ServiceContext.current?.logger?.notice("Resolving package dependencies using xcodebuild")
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

        try system.run(
            arguments,
            verbose: false,
            environment: System.shared.env,
            redirection: .stream(stdout: { bytes in
                let output = String(decoding: bytes, as: Unicode.UTF8.self)
                ServiceContext.current?.logger?.debug("\(output)")
            }, stderr: { bytes in
                let error = String(decoding: bytes, as: Unicode.UTF8.self)
                ServiceContext.current?.logger?.error("\(error)")
            })
        )

        if try await !fileSystem.exists(rootPackageResolvedPath), try await fileSystem.exists(workspacePackageResolvedPath) {
            try await fileSystem.copy(workspacePackageResolvedPath, to: rootPackageResolvedPath)
            if try await !fileSystem.exists(workspacePackageResolvedPath) {
                try await fileSystem.createSymbolicLink(from: workspacePackageResolvedPath, to: rootPackageResolvedPath)
            }
        }
    }
}
