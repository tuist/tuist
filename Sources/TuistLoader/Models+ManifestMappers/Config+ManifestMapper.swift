import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Config {
    /// Maps a ProjectDescription.Config instance into a TuistGraph.Config model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config.
    ///   - path: The path of the config file.
    static func from(manifest: ProjectDescription.Config, at path: AbsolutePath) throws -> TuistGraph.Config {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let generationOptions = try TuistGraph.Config.GenerationOptions.from(manifest: manifest.generationOptions)
        let compatibleXcodeVersions = TuistGraph.CompatibleXcodeVersions.from(manifest: manifest.compatibleXcodeVersions)
        let plugins = try manifest.plugins.map { try PluginLocation.from(manifest: $0, generatorPaths: generatorPaths) }
        let swiftVersion: TSCUtility.Version?
        if let configuredVersion = manifest.swiftVersion {
            swiftVersion = TSCUtility.Version(configuredVersion.major, configuredVersion.minor, configuredVersion.patch)
        } else {
            swiftVersion = nil
        }

        var cloud: TuistGraph.Cloud?
        if let manifestCloud = manifest.cloud {
            cloud = try TuistGraph.Cloud.from(manifest: manifestCloud)
        }

        var cache: TuistGraph.Cache?
        if let manifestCache = manifest.cache {
            cache = try TuistGraph.Cache.from(manifest: manifestCache, generatorPaths: generatorPaths)
        }

        return TuistGraph.Config(
            compatibleXcodeVersions: compatibleXcodeVersions,
            cloud: cloud,
            cache: cache,
            swiftVersion: swiftVersion,
            plugins: plugins,
            generationOptions: generationOptions,
            path: path
        )
    }
}

extension TuistGraph.Config.GenerationOptions {
    /// Maps a ProjectDescription.Config.GenerationOptions instance into a TuistGraph.Config.GenerationOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config generation options
    static func from(manifest: ProjectDescription.Config.GenerationOptions) throws -> TuistGraph.Config.GenerationOptions {
        .init(
            resolveDependenciesWithSystemScm: manifest.resolveDependenciesWithSystemScm,
            disablePackageVersionLocking: manifest.disablePackageVersionLocking
        )
    }
}
