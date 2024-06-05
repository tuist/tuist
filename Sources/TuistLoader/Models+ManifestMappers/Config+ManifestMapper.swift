import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.Config {
    /// Maps a ProjectDescription.Config instance into a XcodeGraph.Config model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config.
    ///   - path: The path of the config file.
    static func from(manifest: ProjectDescription.Config, at path: AbsolutePath) throws -> XcodeGraph.Config {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let generationOptions = try XcodeGraph.Config.GenerationOptions.from(
            manifest: manifest.generationOptions,
            generatorPaths: generatorPaths
        )
        let compatibleXcodeVersions = XcodeGraph.CompatibleXcodeVersions.from(manifest: manifest.compatibleXcodeVersions)
        let plugins = try manifest.plugins.map { try PluginLocation.from(manifest: $0, generatorPaths: generatorPaths) }
        let swiftVersion: TSCUtility.Version?
        if let configuredVersion = manifest.swiftVersion {
            swiftVersion = TSCUtility.Version(configuredVersion.major, configuredVersion.minor, configuredVersion.patch)
        } else {
            swiftVersion = nil
        }

        var cloud: XcodeGraph.Cloud?
        if let manifestCloud = manifest.cloud {
            cloud = try XcodeGraph.Cloud.from(manifest: manifestCloud)
        }

        return XcodeGraph.Config(
            compatibleXcodeVersions: compatibleXcodeVersions,
            cloud: cloud,
            swiftVersion: swiftVersion,
            plugins: plugins,
            generationOptions: generationOptions,
            path: path
        )
    }
}

extension XcodeGraph.Config.GenerationOptions {
    /// Maps a ProjectDescription.Config.GenerationOptions instance into a XcodeGraph.Config.GenerationOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config generation options
    ///   - generatorPaths: Generator paths
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.Config.GenerationOptions {
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
            staticSideEffectsWarningTargets: XcodeGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets
                .from(manifest: manifest.staticSideEffectsWarningTargets),
            enforceExplicitDependencies: manifest.enforceExplicitDependencies,
            defaultConfiguration: manifest.defaultConfiguration
        )
    }
}

extension XcodeGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets {
    /// Maps a ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets instance into a
    /// XcodeGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config static side effects warning targets option
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets
    ) -> XcodeGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets {
        switch manifest {
        case .all: return .all
        case .none: return .none
        case let .excluding(excludedTargets): return .excluding(excludedTargets)
        }
    }
}
