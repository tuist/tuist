import Foundation
import ProjectDescription
import TSCBasic
import TuistDependencies
import TuistLoader
import TuistSupport

final class PluginArchiveService {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let manifestLoader: ManifestLoading
    private let fileArchiverFactory: FileArchivingFactorying

    init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        manifestLoader: ManifestLoading = ManifestLoader(),
        fileArchiverFactory: FileArchivingFactorying = FileArchivingFactory()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.manifestLoader = manifestLoader
        self.fileArchiverFactory = fileArchiverFactory
    }

    func run(path: String?) throws {
        let path = try self.path(path)

        let packageInfo = try swiftPackageManagerController.loadPackageInfo(at: path)
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
            logger
                .warning("No tasks found - make sure you have executable products with `tuist-` prefix defined in your manifest.")
            return
        }

        let plugin = try manifestLoader.loadPlugin(at: path)

        try FileHandler.shared.inTemporaryDirectory { temporaryDirectory in
            try archiveProducts(
                taskProducts: taskProducts,
                path: path,
                plugin: plugin,
                in: temporaryDirectory
            )
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path = path {
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
    ) throws {
        let artifactsPath = temporaryDirectory.appending(component: "artifacts")
        try taskProducts
            .forEach { product in
                logger.notice("Building \(product)...")
                try swiftPackageManagerController.buildFatReleaseBinary(
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
        let temporaryZipPath = try archiver.zip(name: zipName)
        let zipPath = path.appending(component: zipName)
        if FileHandler.shared.exists(zipPath) {
            try FileHandler.shared.delete(zipPath)
        }
        try FileHandler.shared.copy(
            from: temporaryZipPath,
            to: zipPath
        )
        try archiver.delete()

        logger.notice(
            "Plugin was successfully archived. Create a new Github release and attach the file \(zipPath.pathString) as an artifact.",
            metadata: .success
        )
    }
}
