import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistDependencies
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistPlugin
import TuistSupport
import XcodeGraph

@Mockable
protocol InstallServicing {
    func run(
        path: String?,
        update: Bool,
        passthroughArguments: [String]
    ) async throws
}

struct InstallService: InstallServicing {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator
    private let manifestLoader: ManifestLoading
    private let manifestFilesLocator: ManifestFilesLocating
    private let fileSystem: FileSysteming

    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator =
            SwiftPackageManagerScratchDirectoryLocator(),
        manifestLoader: ManifestLoading = ManifestLoader.current,
        fileSystem: FileSysteming = FileSystem(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.swiftPackageManagerScratchDirectoryLocator = swiftPackageManagerScratchDirectoryLocator
        self.manifestLoader = manifestLoader
        self.fileSystem = fileSystem
        self.manifestFilesLocator = manifestFilesLocator
    }

    func run(
        path: String?,
        update: Bool,
        passthroughArguments: [String]
    ) async throws {
        let path = try await self.path(path)

        try await fetchPlugins(path: path)
        try await fetchDependencies(path: path, update: update, passthroughArguments: passthroughArguments)
    }

    // MARK: - Helpers

    private func path(_ path: String?) async throws -> AbsolutePath {
        try await Environment.current.pathRelativeToWorkingDirectory(path)
    }

    private func fetchPlugins(path: AbsolutePath) async throws {
        Logger.current.notice("Resolving and fetching plugins.", metadata: .section)

        let config = try await configLoader.loadConfig(path: path)
        if let generatedProjectOptions = config.project.generatedProject {
            _ = try await pluginService.loadPlugins(using: generatedProjectOptions)
        }

        AlertController.current.success(.alert("Plugins resolved and fetched successfully."))
    }

    private func fetchDependencies(path: AbsolutePath, update: Bool, passthroughArguments: [String]) async throws {
        guard let packageManifestPath = try await manifestFilesLocator.locatePackageManifest(at: path)
        else {
            return
        }

        let config = try await configLoader.loadConfig(path: path)

        let mergedArguments = arguments(config: config, passthroughArguments: passthroughArguments)
        let scratchDirectory = try await swiftPackageManagerScratchDirectory(
            packagePath: packageManifestPath.parentDirectory,
            arguments: mergedArguments
        )

        if update {
            Logger.current.notice("Updating dependencies.", metadata: .section)

            try await swiftPackageManagerController.update(
                at: packageManifestPath.parentDirectory,
                arguments: mergedArguments,
                printOutput: true
            )
        } else {
            Logger.current.notice("Resolving and fetching dependencies.", metadata: .section)

            try await swiftPackageManagerController.resolve(
                at: packageManifestPath.parentDirectory,
                arguments: mergedArguments,
                printOutput: true
            )
        }

        try await savePackageResolved(
            at: packageManifestPath.parentDirectory,
            scratchDirectory: scratchDirectory
        )
        var visitedPackageFolders: Set<String> = []
        var knownPackageIdentities: Set<String> = []
        try await resolveLocalPackageDependencies(
            scratchDirectory: scratchDirectory,
            update: update,
            arguments: SwiftPackageManagerArguments.removingCustomScratchPathArguments(mergedArguments),
            knownPackageIdentities: &knownPackageIdentities,
            visitedPackageFolders: &visitedPackageFolders
        )
    }

    private func arguments(config: Tuist, passthroughArguments: [String]) -> [String] {
        let configArguments = config.project.generatedProject?.installOptions.passthroughSwiftPackageManagerArguments ?? []
        // Passthrough arguments come last so duplicate SwiftPM options can be overridden by the command line.
        return configArguments + passthroughArguments
    }

    private func swiftPackageManagerScratchDirectory(
        packagePath: AbsolutePath,
        arguments: [String]
    ) async throws -> AbsolutePath {
        try swiftPackageManagerScratchDirectoryLocator.locate(
            packagePath: packagePath,
            arguments: arguments,
            environment: Environment.current.variables,
            workingDirectory: try await Environment.current.currentWorkingDirectory()
        )
    }

    private func savePackageResolved(
        at path: AbsolutePath,
        scratchDirectory: AbsolutePath
    ) async throws {
        let sourcePath = path.appending(component: Constants.SwiftPackageManager.packageResolvedName)
        guard try await fileSystem.exists(sourcePath) else { return }

        let destinationPath = scratchDirectory.appending(components: [
            Constants.DerivedDirectory.name,
            Constants.SwiftPackageManager.packageResolvedName,
        ])
        if try await !fileSystem.exists(destinationPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: destinationPath.parentDirectory)
        }
        if try await fileSystem.exists(destinationPath) {
            try await fileSystem.remove(destinationPath)
        }
        try await fileSystem.copy(sourcePath, to: destinationPath)
    }

    private func resolveLocalPackageDependencies(
        scratchDirectory: AbsolutePath,
        update: Bool,
        arguments: [String],
        knownPackageIdentities: inout Set<String>,
        visitedPackageFolders: inout Set<String>
    ) async throws {
        guard let workspaceState = try await workspaceState(scratchDirectory: scratchDirectory) else {
            return
        }
        knownPackageIdentities.formUnion(
            workspaceState.object.dependencies.map { $0.packageRef.identity.lowercased() }
        )

        for dependency in workspaceState.object.dependencies
            where isLocalDependencyKind(dependency.packageRef.kind)
        {
            guard let packageFolder = localPackageFolder(for: dependency, scratchDirectory: scratchDirectory),
                  visitedPackageFolders.insert(packageFolder.pathString).inserted
            else {
                continue
            }

            let localPackageInfo = try await manifestLoader.loadPackage(
                at: packageFolder,
                disableSandbox: true
            )
            let shouldResolveLocalPackage = shouldResolveLocalPackage(
                packageInfo: localPackageInfo,
                knownPackageIdentities: knownPackageIdentities
            )

            let localScratchDirectory = try await swiftPackageManagerScratchDirectory(
                packagePath: packageFolder,
                arguments: arguments
            )
            if shouldResolveLocalPackage {
                if update {
                    try await swiftPackageManagerController.update(
                        at: packageFolder,
                        arguments: arguments,
                        printOutput: true
                    )
                } else {
                    try await swiftPackageManagerController.resolve(
                        at: packageFolder,
                        arguments: arguments,
                        printOutput: true
                    )
                }

                try await savePackageResolved(at: packageFolder, scratchDirectory: localScratchDirectory)
            }
            try await resolveLocalPackageDependencies(
                scratchDirectory: localScratchDirectory,
                update: update,
                arguments: arguments,
                knownPackageIdentities: &knownPackageIdentities,
                visitedPackageFolders: &visitedPackageFolders
            )
        }
    }

    private func shouldResolveLocalPackage(
        packageInfo: PackageInfo,
        knownPackageIdentities: Set<String>
    ) -> Bool {
        let missingPackageDependencies = Set(packageInfo.dependencies.map { $0.identity.lowercased() })
            .subtracting(knownPackageIdentities)
        let hasRemoteBinaryTargets = packageInfo.targets.contains { $0.url != nil }

        return !missingPackageDependencies.isEmpty || hasRemoteBinaryTargets
    }

    private func workspaceState(scratchDirectory: AbsolutePath) async throws -> SwiftPackageManagerWorkspaceState? {
        let workspaceStatePath = scratchDirectory.appending(component: "workspace-state.json")
        guard try await fileSystem.exists(workspaceStatePath) else {
            return nil
        }

        return try JSONDecoder().decode(
            SwiftPackageManagerWorkspaceState.self,
            from: try await fileSystem.readFile(at: workspaceStatePath)
        )
    }

    private func localPackageFolder(
        for dependency: SwiftPackageManagerWorkspaceState.Dependency,
        scratchDirectory: AbsolutePath
    ) -> AbsolutePath? {
        guard let path = dependency.packageRef.path ?? dependency.packageRef.location else {
            return nil
        }
        return try? AbsolutePath(
            validating: sanitizedSwiftPackageManagerPath(path),
            relativeTo: scratchDirectory
        )
    }

    private func isLocalDependencyKind(_ kind: String) -> Bool {
        ["local", "fileSystem", "localSourceControl"].contains(kind)
    }

    private func sanitizedSwiftPackageManagerPath(_ path: String) -> String {
        String(path.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .replacingOccurrences(of: "/private/var", with: "/var")
    }
}
