import FileSystem
import Foundation
import Path
import TuistCore
import TuistSupport

public protocol SwiftPackageManagerInteracting {
    func install(
        graphTraverser: GraphTraversing,
        workspaceName: String,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions
    ) async throws
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

    public func install(
        graphTraverser: GraphTraversing,
        workspaceName: String,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions = .default
    ) async throws {
        try await generatePackageDependencyManager(
            at: graphTraverser.path,
            workspaceName: workspaceName,
            configGeneratedProjectOptions: configGeneratedProjectOptions,
            graphTraverser: graphTraverser
        )
    }

    private func generatePackageDependencyManager(
        at path: AbsolutePath,
        workspaceName: String,
        configGeneratedProjectOptions: TuistGeneratedProjectOptions,
        graphTraverser: GraphTraversing
    ) async throws {
        guard !configGeneratedProjectOptions.generationOptions.disablePackageVersionLocking,
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
        Logger.current.notice("Resolving package dependencies using xcodebuild")
        // -list parameter is a workaround to resolve package dependencies for given workspace without specifying scheme
        var arguments = ["xcodebuild", "-resolvePackageDependencies"]

        // This allows using the system-defined git credentials instead of using Xcode's accounts permissions
        if configGeneratedProjectOptions.generationOptions.resolveDependenciesWithSystemScm {
            arguments.append(contentsOf: ["-scmProvider", "system"])
        }

        // Set specific clone directory for Xcode managed SPM dependencies
        if let clonedSourcePackagesDirPath = configGeneratedProjectOptions.generationOptions.clonedSourcePackagesDirPath {
            let workspace = (workspaceName as NSString).deletingPathExtension
            let path = "\(clonedSourcePackagesDirPath.pathString)/\(workspace)"
            arguments.append(contentsOf: ["-clonedSourcePackagesDirPath", path])
        }

        arguments.append(contentsOf: configGeneratedProjectOptions.generationOptions.additionalPackageResolutionArguments)

        arguments.append(contentsOf: ["-workspace", workspacePath.pathString, "-list"])

        try system.run(
            arguments,
            verbose: false,
            environment: Environment.current.variables,
            redirection: .stream(stdout: { bytes in
                let output = String(decoding: bytes, as: Unicode.UTF8.self)
                Logger.current.debug("\(output)")
            }, stderr: { bytes in
                let error = String(decoding: bytes, as: Unicode.UTF8.self)
                Logger.current.error("\(error)")
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
