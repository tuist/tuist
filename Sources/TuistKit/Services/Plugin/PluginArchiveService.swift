import FileSystem
import Foundation
import Path
import ProjectDescription
import ServiceContextModule
import TuistDependencies
import TuistLoader
import TuistSupport

final class PluginArchiveService {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let packageInfoLoader: PackageInfoLoading
    private let manifestLoader: ManifestLoading
    private let fileArchiverFactory: FileArchivingFactorying
    private let fileSystem: FileSystem

    init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        packageInfoLoader: PackageInfoLoading = PackageInfoLoader(),
        manifestLoader: ManifestLoading = ManifestLoader(),
        fileArchiverFactory: FileArchivingFactorying = FileArchivingFactory(),
        fileSystem: FileSystem = FileSystem()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.packageInfoLoader = packageInfoLoader
        self.manifestLoader = manifestLoader
        self.fileArchiverFactory = fileArchiverFactory
        self.fileSystem = fileSystem
    }

    func run(path: String?) async throws {
        let path = try self.path(path)

        let packageInfo = try await packageInfoLoader.loadPackageInfo(at: path)
        let taskProducts = packageInfo.products
            .filter {
                switch $0.type {
                case .executable:
                    return true
                case .library, .plugin, .test:
                    return false
                }
            }
            .map(\.name)
            .filter { $0.hasPrefix("tuist-") }

        if taskProducts.isEmpty {
            ServiceContext.current?.logger?
                .warning("No tasks found - make sure you have executable products with `tuist-` prefix defined in your manifest.")
            return
        }

        let plugin = try await manifestLoader.loadPlugin(at: path)

        try await FileHandler.shared.inTemporaryDirectory { temporaryDirectory in
            try await self.archiveProducts(
                taskProducts: taskProducts,
                path: path,
                plugin: plugin,
                in: temporaryDirectory
            )
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func archiveProducts(
        taskProducts: [String],
        path: AbsolutePath,
        plugin: Plugin,
        in temporaryDirectory: AbsolutePath
    ) async throws {
        let artifactsPath = temporaryDirectory.appending(component: "artifacts")
        for product in taskProducts {
            ServiceContext.current?.logger?.notice("Building \(product)...")
            try await swiftPackageManagerController.buildFatReleaseBinary(
                packagePath: path,
                product: product,
                buildPath: temporaryDirectory.appending(component: "build"),
                outputPath: artifactsPath
            )
        }
        let archiver = try fileArchiverFactory.makeFileArchiver(
            for: taskProducts
                .map(artifactsPath.appending)
        )
        let zipName = "\(plugin.name).tuist-plugin.zip"
        let temporaryZipPath = try await archiver.zip(name: zipName)
        let zipPath = path.appending(component: zipName)
        if try await fileSystem.exists(zipPath) {
            try await fileSystem.remove(zipPath)
        }
        try await fileSystem.copy(
            temporaryZipPath,
            to: zipPath
        )
        try await archiver.delete()

        ServiceContext.current?.alerts?
            .append(
                .success(
                    .alert(
                        "Plugin was successfully archived. Create a new Github release and attach the file \(zipPath.pathString) as an artifact."
                    )
                )
            )
    }
}
