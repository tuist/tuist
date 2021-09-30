import Foundation
import TuistSupport
import TuistDependencies
import TuistLoader

final class PluginsArchiveService {
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
    
    func run() throws {
        // TODO: Pass path
        let path = FileHandler.shared.currentPath
        
        let packageInfo = try swiftPackageManagerController.loadPackageInfo(at: path)
        let executableProducts = packageInfo.products
            .filter {
                switch $0.type {
                case .executable:
                    return true
                case .library, .plugin, .test:
                    return false
                }
            }
            .map(\.name)
        
        let plugin = try manifestLoader.loadPlugin(at: path)
       
        try FileHandler.shared.inTemporaryDirectory { temporaryDirectory in
            let artifactsPath = temporaryDirectory.appending(component: "artifacts")
            try executableProducts
                .filter { $0.hasPrefix("tuist-") }
                .forEach { product in
                try swiftPackageManagerController.buildFatReleaseBinary(
                    packagePath: path,
                    product: product,
                    buildPath: temporaryDirectory.appending(component: "build"),
                    outputPath: artifactsPath
                )
            }
            let archiver = try fileArchiverFactory.makeFileArchiver(
                for: executableProducts
                    .map(artifactsPath.appending)
            )
            let zipName = "\(plugin.name).tuist-plugin.zip"
            let zipPath = try archiver.zip(name: zipName)
            try FileHandler.shared.copy(
                from: zipPath,
                to: path.appending(component: zipName)
            )
        }
    }
}

