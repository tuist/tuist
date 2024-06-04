import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import XcodeProjectGenerator
import TuistSupport

extension XcodeProjectGenerator.Config {
    /// Maps a ProjectDescription.Config instance into a XcodeProjectGenerator.Config model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config.
    ///   - path: The path of the config file.
    static func from(manifest: ProjectDescription.Config, at path: AbsolutePath) throws -> XcodeProjectGenerator.Config {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let generationOptions = try XcodeProjectGenerator.Config.GenerationOptions.from(
            manifest: manifest.generationOptions,
            generatorPaths: generatorPaths
        )
        let compatibleXcodeVersions = XcodeProjectGenerator.CompatibleXcodeVersions.from(manifest: manifest.compatibleXcodeVersions)
        let plugins = try manifest.plugins.map { try PluginLocation.from(manifest: $0, generatorPaths: generatorPaths) }
        let swiftVersion: TSCUtility.Version?
        if let configuredVersion = manifest.swiftVersion {
            swiftVersion = TSCUtility.Version(configuredVersion.major, configuredVersion.minor, configuredVersion.patch)
        } else {
            swiftVersion = nil
        }

        var cloud: XcodeProjectGenerator.Cloud?
        if let manifestCloud = manifest.cloud {
            cloud = try XcodeProjectGenerator.Cloud.from(manifest: manifestCloud)
        }

        return XcodeProjectGenerator.Config(
            compatibleXcodeVersions: compatibleXcodeVersions,
            cloud: cloud,
            swiftVersion: swiftVersion,
            plugins: plugins,
            generationOptions: generationOptions,
            path: path
        )
    }
}

extension XcodeProjectGenerator.Config.GenerationOptions {
    /// Maps a ProjectDescription.Config.GenerationOptions instance into a XcodeProjectGenerator.Config.GenerationOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config generation options
    ///   - generatorPaths: Generator paths
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeProjectGenerator.Config.GenerationOptions {
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
            staticSideEffectsWarningTargets: XcodeProjectGenerator.Config.GenerationOptions.StaticSideEffectsWarningTargets
                .from(manifest: manifest.staticSideEffectsWarningTargets),
            enforceExplicitDependencies: manifest.enforceExplicitDependencies,
            defaultConfiguration: manifest.defaultConfiguration
        )
    }
}

extension XcodeProjectGenerator.Config.GenerationOptions.StaticSideEffectsWarningTargets {
    /// Maps a ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets instance into a
    /// XcodeProjectGenerator.Config.GenerationOptions.StaticSideEffectsWarningTargets model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config static side effects warning targets option
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets
    ) -> XcodeProjectGenerator.Config.GenerationOptions.StaticSideEffectsWarningTargets {
        switch manifest {
        case .all: return .all
        case .none: return .none
        case let .excluding(excludedTargets): return .excluding(excludedTargets)
        }
    }
}
