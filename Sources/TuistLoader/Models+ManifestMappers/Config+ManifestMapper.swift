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
        let generationOptions = try TuistGraph.Config.GenerationOptions.from(
            manifest: manifest.generationOptions,
            generatorPaths: generatorPaths
        )
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

        var dependenciesOptions: TuistGraph.Config.DependenciesOptions?
        if let manifestDependenciesOptions = manifest.dependenciesOptions {
            dependenciesOptions = try TuistGraph.Config.DependenciesOptions.from(
                manifest: manifestDependenciesOptions,
                generatorPaths: generatorPaths
            )
        }

        return TuistGraph.Config(
            compatibleXcodeVersions: compatibleXcodeVersions,
            cloud: cloud,
            cache: cache,
            swiftVersion: swiftVersion,
            plugins: plugins,
            generationOptions: generationOptions,
            path: path,
            dependenciesOptions: dependenciesOptions
        )
    }
}

extension TuistGraph.Config.GenerationOptions {
    /// Maps a ProjectDescription.Config.GenerationOptions instance into a TuistGraph.Config.GenerationOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config generation options
    ///   - generatorPaths: Generator paths
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.Config.GenerationOptions {
        let clonedSourcePackagesDirPath: AbsolutePath? = try {
            if let path = manifest.clonedSourcePackagesDirPath {
                return try generatorPaths.resolve(path: path)
            } else {
                return nil
            }
        }()
        return .init(
            resolveDependenciesWithSystemScm: manifest.resolveDependenciesWithSystemScm,
            disablePackageVersionLocking: manifest.disablePackageVersionLocking,
            clonedSourcePackagesDirPath: clonedSourcePackagesDirPath
        )
    }
}

extension TuistGraph.Config.DependenciesOptions {
    /// Maps a ProjectDescription.Config.DependenciesOptions instance into a TuistGraph.Config.DependenciesOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config dependencies options
    ///   - generatorPaths: Generator paths
    static func from(
        manifest: ProjectDescription.Config.DependenciesOptions,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.Config.DependenciesOptions {
        let packagePath: AbsolutePath = try generatorPaths.resolve(path: manifest.packagePath)
        let platforms = try manifest.platforms.map { try TuistGraph.Platform.from(manifest: $0) }
        let productTypes: [String: TuistGraph.Product] = manifest.productTypes.mapValues(TuistGraph.Product.from)
        let baseSettings: TuistGraph.Settings = try TuistGraph.Settings.from(
            manifest: manifest.baseSettings,
            generatorPaths: generatorPaths
        )
        let targetSettings: [String: TuistGraph.SettingsDictionary] = manifest.targetSettings
            .mapValues { $0.mapValues(TuistGraph.SettingValue.from) }
        return TuistGraph.Config.DependenciesOptions(
            packagePath: packagePath,
            platforms: Set(platforms),
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings
        )
    }
}
