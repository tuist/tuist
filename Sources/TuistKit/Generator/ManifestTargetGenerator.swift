import Basic
import Foundation
import TuistCore
import TuistGenerator

protocol ManifestTargetGenerating {
    func generateManifestTarget(for project: String, at path: AbsolutePath) throws -> Target
}

final class ManifestTargetGenerator: ManifestTargetGenerating {
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
        let manifests = manifestLoader.manifests(at: path)

        return Target(name: "\(project)_Manifest",
                      platform: .macOS,
                      product: .staticFramework,
                      productName: "\(project)_Manifest",
                      bundleId: "io.tuist.manifests.${PRODUCT_NAME:rfc1034identifier}",
                      settings: settings,
                      sources: manifests.map { (path: path.appending(component: $0.fileName), compilerFlags: nil) },
                      filesGroup: .group(name: "Manifest"))
    }

    // MARK: - Private

    private func manifestTargetBuildSettings() throws -> [String: Configuration.Value] {
        let frameworkParentDirectory = try resourceLocator.projectDescription().parentDirectory
        var buildSettings = [String: Configuration.Value]()
        buildSettings["FRAMEWORK_SEARCH_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["LIBRARY_SEARCH_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["SWIFT_INCLUDE_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["SWIFT_VERSION"] = .string(Constants.swiftVersion)
        return buildSettings
    }
}
