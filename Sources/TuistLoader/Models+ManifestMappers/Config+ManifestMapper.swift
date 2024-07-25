import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph

enum ConfigManifestMapperError: FatalError {
    /// Thrown when the server URL is invalid.
    case invalidServerURL(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidServerURL: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .invalidServerURL(url):
            return "The server URL '\(url)' is not a valid URL"
        }
    }
}

extension TuistCore.Config {
    /// Maps a ProjectDescription.Config instance into a XcodeGraph.Config model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config.
    ///   - path: The path of the config file.
    static func from(manifest: ProjectDescription.Config, at path: AbsolutePath) throws -> TuistCore.Config {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        var generationOptions = try TuistCore.Config.GenerationOptions.from(
            manifest: manifest.generationOptions,
            generatorPaths: generatorPaths
        )
        let compatibleXcodeVersions = TuistCore.CompatibleXcodeVersions.from(manifest: manifest.compatibleXcodeVersions)
        let plugins = try manifest.plugins.map { try PluginLocation.from(manifest: $0, generatorPaths: generatorPaths) }
        let swiftVersion: TSCUtility.Version?
        if let configuredVersion = manifest.swiftVersion {
            swiftVersion = TSCUtility.Version(configuredVersion.major, configuredVersion.minor, configuredVersion.patch)
        } else {
            swiftVersion = nil
        }

        let fullHandle: String?
        let urlString: String
        if let manifestCloud = manifest.cloud {
            fullHandle = manifestCloud.projectId
            urlString = manifestCloud.url
            generationOptions.optionalAuthentication = manifestCloud.options.contains(.optional)
        } else {
            fullHandle = manifest.fullHandle
            urlString = manifest.url
        }

        guard let url = URL(string: urlString.dropSuffix("/")) else {
            throw ConfigManifestMapperError.invalidServerURL(manifest.url)
        }

        return TuistCore.Config(
            compatibleXcodeVersions: compatibleXcodeVersions,
            fullHandle: fullHandle,
            url: url,
            swiftVersion: swiftVersion.map { .init(stringLiteral: $0.description) },
            plugins: plugins,
            generationOptions: generationOptions,
            path: path
        )
    }
}

extension TuistCore.Config.GenerationOptions {
    /// Maps a ProjectDescription.Config.GenerationOptions instance into a XcodeGraph.Config.GenerationOptions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config generation options
    ///   - generatorPaths: Generator paths
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions,
        generatorPaths: GeneratorPaths
    ) throws -> TuistCore.Config.GenerationOptions {
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
            staticSideEffectsWarningTargets: TuistCore.Config.GenerationOptions.StaticSideEffectsWarningTargets
                .from(manifest: manifest.staticSideEffectsWarningTargets),
            enforceExplicitDependencies: manifest.enforceExplicitDependencies,
            defaultConfiguration: manifest.defaultConfiguration,
            optionalAuthentication: manifest.optionalAuthentication
        )
    }
}

extension TuistCore.Config.GenerationOptions.StaticSideEffectsWarningTargets {
    /// Maps a ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets instance into a
    /// XcodeGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config static side effects warning targets option
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets
    ) -> TuistCore.Config.GenerationOptions.StaticSideEffectsWarningTargets {
        switch manifest {
        case .all: return .all
        case .none: return .none
        case let .excluding(excludedTargets): return .excluding(excludedTargets)
        }
    }
}
