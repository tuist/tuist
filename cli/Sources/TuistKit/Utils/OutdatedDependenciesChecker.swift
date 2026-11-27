import FileSystem
import Foundation
import Mockable
import Path
import TuistConfigLoader
import TuistConstants
import TuistEnvironment
import TuistLoader
import TuistSupport

@Mockable
protocol OutdatedDependenciesChecking {
    func packageDependenciesAreOutdated(at path: AbsolutePath) async throws -> Bool
}

struct OutdatedDependenciesChecker: OutdatedDependenciesChecking {
    private let manifestFilesLocator: ManifestFilesLocating
    private let fileSystem: FileSysteming
    private let configLoader: ConfigLoading
    private let swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator
    private let swiftPackageManagerController: SwiftPackageManagerControlling

    init(
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        fileSystem: FileSysteming = FileSystem(),
        configLoader: ConfigLoading = ConfigLoader(),
        swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator =
            SwiftPackageManagerScratchDirectoryLocator(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController()
    ) {
        self.manifestFilesLocator = manifestFilesLocator
        self.fileSystem = fileSystem
        self.configLoader = configLoader
        self.swiftPackageManagerScratchDirectoryLocator = swiftPackageManagerScratchDirectoryLocator
        self.swiftPackageManagerController = swiftPackageManagerController
    }

    func packageDependenciesAreOutdated(at path: AbsolutePath) async throws -> Bool {
        guard let packageManifestPath = try await manifestFilesLocator.locatePackageManifest(at: path) else {
            return false
        }

        let packageDirectory = packageManifestPath.parentDirectory
        let config = try await configLoader.loadConfig(path: path)
        let arguments = config.project.generatedProject?.installOptions.passthroughSwiftPackageManagerArguments ?? []
        let scratchDirectory = try swiftPackageManagerScratchDirectoryLocator.locate(
            packagePath: packageDirectory,
            arguments: arguments,
            environment: Environment.current.variables,
            workingDirectory: try await Environment.current.currentWorkingDirectory()
        )
        let currentPackageResolvedPath = packageDirectory
            .appending(component: Constants.SwiftPackageManager.packageResolvedName)
        let savedPackageResolvedPath = scratchDirectory.appending(components: [
            Constants.DerivedDirectory.name,
            Constants.SwiftPackageManager.packageResolvedName,
        ])

        var currentData: Data?
        if try await fileSystem.exists(currentPackageResolvedPath) {
            currentData = try await fileSystem.readFile(at: currentPackageResolvedPath)
        }

        var savedData: Data?
        if try await fileSystem.exists(savedPackageResolvedPath) {
            savedData = try await fileSystem.readFile(at: savedPackageResolvedPath)
        }

        if currentData != savedData { return true }
        if try await hasPrunedCacheLinks(scratchDirectory: scratchDirectory) { return true }

        // A toolchain update leaves the lockfile as is, but its compiler cannot import the recorded prebuilts.
        return try await swiftPackageManagerController.recordsOutdatedPrebuilts(
            at: packageDirectory,
            scratchDirectory: scratchDirectory
        )
    }

    /// SwifterPM links checkouts, binary artifacts and registry downloads into the shared cache,
    /// which drops entries nothing has used for a while. A project nobody installed in since then
    /// still matches its `Package.resolved` but links to nothing, so it needs `tuist install`.
    private func hasPrunedCacheLinks(scratchDirectory: AbsolutePath) async throws -> Bool {
        let links = try await entries(in: scratchDirectory.appending(component: "checkouts"), depth: 1)
            + entries(in: scratchDirectory.appending(component: "artifacts"), depth: 2)
            + registryDownloads(scratchDirectory: scratchDirectory)
            .map { $0.appending(component: Constants.SwiftPackageManager.packageSwiftName) }
        for link in links where !link.basename.hasPrefix(".") {
            // `exists` follows symbolic links, so a link whose cache entry is gone reads as absent.
            if try await !fileSystem.exists(link) { return true }
        }
        return false
    }

    /// Registry downloads sit at the depth the resolving SwiftPM chose: SwiftPM 6.4.2 and later
    /// add a directory per registry above `<scope>/<name>/<version>`. The workspace state records
    /// each one's location either way.
    private func registryDownloads(scratchDirectory: AbsolutePath) async throws -> [AbsolutePath] {
        struct WorkspaceState: Decodable {
            struct Object: Decodable {
                struct Dependency: Decodable {
                    struct PackageReference: Decodable { let kind: String }
                    let packageRef: PackageReference
                    let subpath: String?
                }

                let dependencies: [Dependency]
            }

            let object: Object
        }

        let statePath = scratchDirectory.appending(component: "workspace-state.json")
        guard try await fileSystem.exists(statePath),
              let state = try? JSONDecoder().decode(WorkspaceState.self, from: await fileSystem.readFile(at: statePath))
        else { return [] }
        let downloads = scratchDirectory.appending(components: "registry", "downloads")
        return state.object.dependencies.filter { $0.packageRef.kind == "registry" }.compactMap {
            try? $0.subpath.map { try downloads.appending(RelativePath(validating: $0)) }
        }
    }

    private func entries(in directory: AbsolutePath, depth: Int) async throws -> [AbsolutePath] {
        guard try await fileSystem.exists(directory, isDirectory: true) else { return [] }
        let children = try await fileSystem.contentsOfDirectory(directory)
            .filter { !$0.basename.hasPrefix(".") }
        guard depth > 1 else { return children }
        var entries: [AbsolutePath] = []
        for child in children {
            entries += try await self.entries(in: child, depth: depth - 1)
        }
        return entries
    }
}
