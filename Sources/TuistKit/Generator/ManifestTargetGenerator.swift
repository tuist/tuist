import Basic
import Foundation
import TuistCore

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
                                debug: nil,
                                release: nil)
        let manifest = try manifestLoader.manifestPath(at: path, manifest: .project)
        return Target(name: "\(project)-Manifest",
                      platform: .macOS,
                      product: .framework,
                      bundleId: "",
                      settings: settings,
                      sources: [manifest],
                      filesGroup: .group(name: "Manifest"))
    }

    func manifestTargetBuildSettings() throws -> [String: String] {
        let frameworkParentDirectory = try resourceLocator.projectDescription().parentDirectory
        var buildSettings = [String: String]()
        buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkParentDirectory.asString
        buildSettings["LIBRARY_SEARCH_PATHS"] = frameworkParentDirectory.asString
        buildSettings["SWIFT_FORCE_DYNAMIC_LINK_STDLIB"] = "YES"
        buildSettings["SWIFT_FORCE_STATIC_LINK_STDLIB"] = "NO"
        buildSettings["SWIFT_INCLUDE_PATHS"] = frameworkParentDirectory.asString
        buildSettings["SWIFT_VERSION"] = Constants.swiftVersion
        buildSettings["LD"] = "/usr/bin/true"
        buildSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "SWIFT_PACKAGE"
        buildSettings["OTHER_SWIFT_FLAGS"] = "-swift-version 4 -I \(frameworkParentDirectory.asString)"
        return buildSettings
    }
}
