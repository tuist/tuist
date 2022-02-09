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

        if let forcedCacheDirectiory = forcedCacheDirectiory {
            cache = cache.map { TuistGraph.Cache(profiles: $0.profiles, path: forcedCacheDirectiory) }
                ?? TuistGraph.Cache(profiles: [], path: forcedCacheDirectiory)
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

    private static var forcedCacheDirectiory: AbsolutePath? {
        ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.forceConfigCacheDirectory].map { AbsolutePath($0) }
    }
}

extension TuistGraph.Config.GenerationOptions {
    /// Maps a ProjectDescription.Config.GenerationOptions instance into a TuistGraph.Config.GenerationOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config generation options
    static func from(manifest: ProjectDescription.Config.GenerationOptions) throws -> TuistGraph.Config.GenerationOptions {
        .init(
            xcodeProjectName: manifest.xcodeProjectName?.description,
            organizationName: manifest.organizationName,
            developmentRegion: manifest.developmentRegion,
            templateMacros: nil, // TODO: ?
            resolveDependenciesWithSystemScm: manifest.resolveDependenciesWithSystemScm,
            disablePackageVersionLocking: manifest.disablePackageVersionLocking
        )
    }
}
