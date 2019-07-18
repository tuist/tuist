import Basic
import Foundation
import TuistCore
import TuistGenerator

protocol ManifestTargetGenerating {
    func generateManifestTarget(for project: String, at path: AbsolutePath) throws -> Target
}

class ManifestTargetGenerator: ManifestTargetGenerating {
    private let manifestLoader: GraphManifestLoading
    private let resourceLocator: ResourceLocating

    init(manifestLoader: GraphManifestLoading,
         resourceLocator: ResourceLocating) {
        self.manifestLoader = manifestLoader
        self.resourceLocator = resourceLocator
    }

    func generateManifestTarget(for project: String,
                                at path: AbsolutePath) throws -> Target {
        let settings = Settings(base: try manifestTargetBuildSettings(),
                                configurations: Settings.default.configurations,
                                defaultSettings: .recommended)
        let projectManifestPath = manifestLoader.manifests(at: path)
            .filter { [Manifest.project, Manifest.tuistConfig].contains($0) }

        return Target(name: "\(project)_Manifest",
                      platform: .macOS,
                      product: .staticFramework,
                      productName: "\(project)_Manifest",
                      bundleId: "io.tuist.manifests.${PRODUCT_NAME:rfc1034identifier}",
                      settings: settings,
                      sources: projectManifestPath.map { (path: path.appending(component: $0.fileName), compilerFlags: nil) },
                      filesGroup: .group(name: "Manifest"))
    }

    func manifestTargetBuildSettings() throws -> [String: String] {
        let frameworkParentDirectory = try resourceLocator.projectDescription().parentDirectory
        var buildSettings = [String: String]()
        buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkParentDirectory.pathString
        buildSettings["LIBRARY_SEARCH_PATHS"] = frameworkParentDirectory.pathString
        buildSettings["SWIFT_INCLUDE_PATHS"] = frameworkParentDirectory.pathString
        buildSettings["SWIFT_VERSION"] = Constants.swiftVersion
        return buildSettings
    }
}
