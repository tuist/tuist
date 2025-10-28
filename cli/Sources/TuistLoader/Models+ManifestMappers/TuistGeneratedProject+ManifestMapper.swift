import Path
import ProjectDescription
import TuistCore

extension TuistCore.TuistGeneratedProjectOptions.GenerationOptions {
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions,
        generatorPaths: GeneratorPaths,
        fullHandle: String?
    ) throws -> Self {
        var additionalPackageResolutionArguments = manifest.additionalPackageResolutionArguments
        if manifest.resolveDependenciesWithSystemScm {
            additionalPackageResolutionArguments.append(contentsOf: ["-scmProvider", "system"])
        }

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
            additionalPackageResolutionArguments: additionalPackageResolutionArguments,
            staticSideEffectsWarningTargets: TuistCore.TuistGeneratedProjectOptions.GenerationOptions
                .StaticSideEffectsWarningTargets
                .from(manifest: manifest.staticSideEffectsWarningTargets),
            enforceExplicitDependencies: manifest.enforceExplicitDependencies,
            defaultConfiguration: manifest.defaultConfiguration,
            optionalAuthentication: manifest.optionalAuthentication,
            buildInsightsDisabled: fullHandle == nil || manifest.buildInsightsDisabled,
            disableSandbox: manifest.disableSandbox,
            includeGenerateScheme: manifest.includeGenerateScheme,
            enableCaching: manifest.enableCaching
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

extension TuistCore.CacheOptions {
    static func from(
        manifest: ProjectDescription.Config.CacheOptions
    ) throws -> Self {
        let profiles = TuistCore.CacheProfiles.from(manifest: manifest.profiles)
        if case let .custom(name) = profiles.defaultProfile, profiles.profileByName[name] == nil {
            throw ConfigManifestMapperError.defaultCacheProfileNotFound(
                profile: name,
                available: Array(profiles.profileByName.keys)
            )
        }
        return .init(
            keepSourceTargets: manifest.keepSourceTargets,
            profiles: profiles
        )
    }
}

extension TuistCore.CacheProfiles {
    static func from(
        manifest: ProjectDescription.CacheProfiles
    ) -> Self {
        .init(
            manifest.profileByName.mapValues { .from(manifest: $0) },
            default: .from(manifest: manifest.defaultProfile)
        )
    }
}

extension TuistCore.CacheProfile {
    static func from(
        manifest: ProjectDescription.CacheProfile
    ) -> Self {
        .init(
            base: .from(manifest: manifest.base),
            targetQueries: manifest.targetQueries.map { .from(manifest: $0) }
        )
    }
}

extension TuistCore.BaseCacheProfile {
    static func from(
        manifest: ProjectDescription.BaseCacheProfile
    ) -> Self {
        switch manifest {
        case .onlyExternal: return .onlyExternal
        case .allPossible: return .allPossible
        case .none: return .none
        }
    }
}

extension TuistCore.CacheProfileType {
    static func from(
        manifest: ProjectDescription.CacheProfileType
    ) -> Self {
        switch manifest {
        case .onlyExternal: return .onlyExternal
        case .allPossible: return .allPossible
        case .none: return .none
        case let .custom(name): return .custom(name)
        }
    }
}

extension TuistCore.TargetQuery {
    static func from(
        manifest: ProjectDescription.TargetQuery
    ) -> Self {
        switch manifest {
        case let .named(name): return .named(name)
        case let .tagged(tag): return .tagged(tag)
        }
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
