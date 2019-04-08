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
                                configurations: Settings.default.configurations)
        let manifest = try manifestLoader.manifestPath(at: path, manifest: .project)
        return Target(name: "\(project)-Manifest",
                      platform: .macOS,
                      product: .staticFramework,
                      bundleId: "io.tuist.manifests.${PRODUCT_NAME:rfc1034identifier}",
                      settings: settings,
                      sources: [manifest],
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
