import Foundation
import TuistSupport
import TuistDependencies
import TuistLoader

final class PluginsArchiveService {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let manifestLoader: ManifestLoading
    
    init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        manifestLoader: ManifestLoading = ManifestLoader()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.manifestLoader = manifestLoader
    }
    
    func run() throws {
        // TODO: Pass path
        let path = FileHandler.shared.currentPath
        let tasksPath = path.appending(component: "Tasks")
        
        let packageInfo = try swiftPackageManagerController.loadPackageInfo(at: tasksPath)
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
        
        try executableProducts
            .forEach { product in
                // TODO: Move to a component
                // TODO: M1 support (take a look at `swift_package_manager.rb` in fourier)
                try System.shared.run(
                    "swift",
                    "build",
                    "--package-path",
                    tasksPath.pathString,
                    "--configuration",
                    "release",
                    "--product",
                    product
                )
            }
        
        let executables = executableProducts.map {
            tasksPath.appending(components: ".build", "release", $0)
        }
        .map(\.pathString)
        
        let plugin = try manifestLoader.loadPlugin(at: path)
        
        let buildPath = path.appending(component: "build")
        if !FileHandler.shared.exists(buildPath) {
            try FileHandler.shared.createFolder(buildPath)
        }
        try System.shared.run(
            [
                "/usr/bin/zip",
                buildPath.appending(component: "\(plugin.name).tuist-plugin.zip").pathString
            ]
            + executables
        )
    }
}

