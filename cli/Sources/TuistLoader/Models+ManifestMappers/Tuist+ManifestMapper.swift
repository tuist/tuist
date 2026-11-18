import Foundation
import Path
import ProjectDescription
import TuistConfig
import TuistCore
import TuistLogging
import TuistSupport

enum ConfigManifestMapperError: FatalError, Equatable {
    /// Thrown when the server URL is invalid.
    case invalidServerURL(String)

    /// Thrown when selective testing selects tests by coverage that isn't uploaded.
    case coverageStrategyRequiresCoverageUpload

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidServerURL, .coverageStrategyRequiresCoverageUpload: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .invalidServerURL(url):
            return "The server URL '\(url)' is not a valid URL"
        case .coverageStrategyRequiresCoverageUpload:
            return "The coverage selective testing strategy selects tests by the coverage test runs upload. Set 'coverage: .coverage(upload: true)' in 'testInsights' or remove the strategy."
        }
    }
}

extension TuistConfig.Tuist {
    /// Maps a ProjectDescription.Config instance into a XcodeGraph.Config model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Tuist config.
    ///   - path: The path of the config file.
    public static func from(
        manifest: ProjectDescription.Config,
        rootDirectory: AbsolutePath,
        at path: AbsolutePath
    ) async throws -> TuistConfig.Tuist {
        let fullHandle = manifest.fullHandle
        let inspectOptions = InspectOptions.from(manifest: manifest.inspectOptions)
        let generatorPaths = GeneratorPaths(manifestDirectory: path, rootDirectory: rootDirectory)
        let network = try makeNetwork(from: manifest, generatorPaths: generatorPaths)
        let xcodeCache = TuistConfig.Tuist.XcodeCache(
            upload: manifest.xcodeCache.upload,
            storeSizeLimit: manifest.xcodeCache.storeSizeLimit?.bytes
        )
        let testInsights = try TuistConfig.Tuist.TestInsights.from(manifest: manifest.testInsights)
        let urlString = manifest.url

        guard let url = URL(string: urlString.dropSuffix("/")) else {
            throw ConfigManifestMapperError.invalidServerURL(manifest.url)
        }

        switch manifest.project {
        case let .tuist(
            compatibleXcodeVersions,
            plugins,
            generationOptions,
            installOptions,
            cacheOptions
        ):
            let generationOptions = try TuistConfig.TuistGeneratedProjectOptions.GenerationOptions.from(
                manifest: generationOptions,
                generatorPaths: generatorPaths,
                fullHandle: manifest.fullHandle
            )
            let cacheOptions = try TuistConfig.CacheOptions.from(manifest: cacheOptions)

            let compatibleXcodeVersions = TuistConfig.CompatibleXcodeVersions.from(manifest: compatibleXcodeVersions)
            let plugins = try plugins.map { try PluginLocation.from(manifest: $0, generatorPaths: generatorPaths) }

            let installOptions = TuistConfig.TuistGeneratedProjectOptions.InstallOptions.from(
                manifest: installOptions
            )

            return TuistConfig.Tuist(
                project: .generated(
                    TuistGeneratedProjectOptions(
                        compatibleXcodeVersions: compatibleXcodeVersions,
                        plugins: plugins,
                        generationOptions: generationOptions,
                        installOptions: installOptions,
                        cacheOptions: cacheOptions
                    )
                ),
                fullHandle: fullHandle,
                inspectOptions: inspectOptions,
                xcodeCache: xcodeCache,
                testInsights: testInsights,
                url: url,
                network: network
            )
        case .xcode:
            return TuistConfig.Tuist(
                project: .xcode(TuistXcodeProjectOptions()),
                fullHandle: fullHandle,
                inspectOptions: inspectOptions,
                xcodeCache: xcodeCache,
                testInsights: testInsights,
                url: url,
                network: network
            )
        }
    }
}

extension TuistConfig.Tuist {
    fileprivate static func makeNetwork(
        from manifest: ProjectDescription.Config,
        generatorPaths: GeneratorPaths
    ) throws -> TuistConfig.Tuist.Network {
        let caCertificate = try manifest.network.caCertificate.map { try generatorPaths.resolve(path: $0).pathString }
        return .init(proxy: manifest.network.proxy, caCertificate: caCertificate)
    }
}

extension TuistConfig.Tuist.TestInsights {
    static func from(manifest: ProjectDescription.Config.TestInsights) throws -> Self {
        let strategy: SelectiveTesting.Strategy? = manifest.selectiveTesting?.strategy == .coverage() ? .coverage : nil
        if strategy == .coverage, !manifest.coverage.upload {
            throw ConfigManifestMapperError.coverageStrategyRequiresCoverageUpload
        }
        return Self(
            coverage: .init(upload: manifest.coverage.upload),
            selectiveTesting: manifest.selectiveTesting.map { _ in SelectiveTesting(strategy: strategy) }
        )
    }
}

extension TuistConfig.InspectOptions {
    static func from(
        manifest: ProjectDescription.Config.InspectOptions
    ) -> Self {
        return .init(
            redundantDependencies: .from(manifest: manifest.redundantDependencies)
        )
    }
}

extension TuistConfig.InspectOptions.RedundantDependencies {
    static func from(
        manifest: ProjectDescription.Config.InspectOptions.RedundantDependencies
    ) -> Self {
        return .init(
            ignoreTagsMatching: manifest.ignoreTagsMatching
        )
    }
}
