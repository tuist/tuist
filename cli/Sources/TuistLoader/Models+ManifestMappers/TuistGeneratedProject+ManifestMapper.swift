import Path
import ProjectDescription
import TuistCore
import Foundation

extension TuistCore.TuistGeneratedProjectOptions.GenerationOptions {
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions,
        generatorPaths: GeneratorPaths,
        fullHandle: String?
    ) throws -> Self {
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
            staticSideEffectsWarningTargets: TuistCore.TuistGeneratedProjectOptions.GenerationOptions
                .StaticSideEffectsWarningTargets
                .from(manifest: manifest.staticSideEffectsWarningTargets),
            enforceExplicitDependencies: manifest.enforceExplicitDependencies,
            defaultConfiguration: manifest.defaultConfiguration,
            optionalAuthentication: manifest.optionalAuthentication,
            buildInsightsDisabled: fullHandle == nil || manifest.buildInsightsDisabled,
            disableSandbox: manifest.disableSandbox,
            includeGenerateScheme: manifest.includeGenerateScheme
        )
    }
}

extension TuistCore.TuistGeneratedProjectOptions.InstallOptions {
    static func from(
        manifest: ProjectDescription.Config.InstallOptions
    ) -> Self {
        return .init(
            passthroughSwiftPackageManagerArguments: manifest.passthroughSwiftPackageManagerArguments
        )
    }
}

enum TuistGeneratedProjectOptionsCacheOptionsError: LocalizedError {
    case nonSupportedConcurrencyValue(String)
    
    var errorDescription: String? {
        switch self {
        case .nonSupportedConcurrencyValue(let value):
            return "Couldn't parse non-supported the following concurrency value from cache options: \(value)"
        }
    }
}

extension TuistCore.TuistGeneratedProjectOptions.CacheOptions {
    static func from(
        manifest: ProjectDescription.Config.CacheOptions
    ) throws -> Self {
        return .init(
            keepSourceTargets: manifest.keepSourceTargets,
            downloadOptions: .init(chunked: manifest.downloadOptions.chunked,
                                   chunkSize: manifest.downloadOptions.chunkSize,
                                   concurrencyLimit: manifest.downloadOptions.concurrencyLimit)
        )
    }
}

extension TuistCore.TuistGeneratedProjectOptions.CacheOptions.DownloadOptions {
    static func from(
        manifest: ProjectDescription.Config.CacheOptions.DownloadOptions
    ) throws -> Self {
        return Self(chunked: manifest.chunked, chunkSize: manifest.chunkSize, concurrencyLimit: manifest.concurrencyLimit)
    }
}

extension TuistCore.TuistGeneratedProjectOptions.GenerationOptions.StaticSideEffectsWarningTargets {
    static func from(manifest: ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets) -> Self {
        switch manifest {
        case .all: return .all
        case .none: return .none
        case let .excluding(excludedTargets): return .excluding(excludedTargets)
        }
    }
}
