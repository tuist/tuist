import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistSupport

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

extension TuistCore.Tuist {
    /// Maps a ProjectDescription.Config instance into a XcodeGraph.Config model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config.
    ///   - path: The path of the config file.
    static func from(
        manifest: ProjectDescription.Config,
        rootDirectory: AbsolutePath,
        at path: AbsolutePath
    ) async throws -> TuistCore.Tuist {
        let fullHandle = manifest.fullHandle
        let inspectOptions = InspectOptions.from(manifest: manifest.inspectOptions)
        let urlString = manifest.url

        guard let url = URL(string: urlString.dropSuffix("/")) else {
            throw ConfigManifestMapperError.invalidServerURL(manifest.url)
        }

        switch manifest.project {
        case let .tuist(
            compatibleXcodeVersions,
            manifestSwiftVersion,
            plugins,
            generationOptions,
            installOptions,
            cacheOptions
        ):
            let generatorPaths = GeneratorPaths(manifestDirectory: path, rootDirectory: rootDirectory)
            let generationOptions = try TuistCore.TuistGeneratedProjectOptions.GenerationOptions.from(
                manifest: generationOptions,
                generatorPaths: generatorPaths,
                fullHandle: manifest.fullHandle
            )
            let cacheOptions = try TuistCore.CacheOptions.from(manifest: cacheOptions)

            let compatibleXcodeVersions = TuistCore.CompatibleXcodeVersions.from(manifest: compatibleXcodeVersions)
            let plugins = try plugins.map { try PluginLocation.from(manifest: $0, generatorPaths: generatorPaths) }
            let swiftVersion: TSCUtility.Version?
            if let configuredVersion = manifestSwiftVersion {
                swiftVersion = TSCUtility.Version(configuredVersion.major, configuredVersion.minor, configuredVersion.patch)
            } else {
                swiftVersion = nil
            }

            let installOptions = TuistCore.TuistGeneratedProjectOptions.InstallOptions.from(
                manifest: installOptions
            )

            return TuistCore.Tuist(
                project: .generated(
                    TuistGeneratedProjectOptions(
                        compatibleXcodeVersions: compatibleXcodeVersions,
                        swiftVersion: swiftVersion.map { .init(stringLiteral: $0.description) },
                        plugins: plugins,
                        generationOptions: generationOptions,
                        installOptions: installOptions,
                        cacheOptions: cacheOptions
                    )
                ),
                fullHandle: fullHandle,
                inspectOptions: inspectOptions,
                url: url
            )
        case .xcode:
            return TuistCore.Tuist(
                project: .xcode(TuistXcodeProjectOptions()),
                fullHandle: fullHandle,
                inspectOptions: inspectOptions,
                url: url
            )
        }
    }
}

extension TuistCore.InspectOptions {
    static func from(
        manifest: ProjectDescription.Config.InspectOptions
    ) -> Self {
        return .init(
            redundantDependencies: .from(manifest: manifest.redundantDependencies)
        )
    }
}

extension TuistCore.InspectOptions.RedundantDependencies {
    static func from(
        manifest: ProjectDescription.Config.InspectOptions.RedundantDependencies
    ) -> Self {
        return .init(
            ignoreTagsMatching: manifest.ignoreTagsMatching
        )
    }
}
