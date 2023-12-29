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
            clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
            staticSideEffectsWarningTargets: TuistGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets
                .from(manifest: manifest.staticSideEffectsWarningTargets),
            enforceExplicitDependencies: manifest.enforceExplicitDependencies
        )
    }
}

extension TuistGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets {
    /// Maps a ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets instance into a
    /// TuistGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config static side effects warning targets option
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets
    ) -> TuistGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets {
        switch manifest {
        case .all: return .all
        case .none: return .none
        case let .excluding(excludedTargets): return .excluding(excludedTargets)
        }
    }
}
