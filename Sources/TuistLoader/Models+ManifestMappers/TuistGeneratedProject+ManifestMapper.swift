import Path
import ProjectDescription
import TuistCore

extension TuistCore.TuistGeneratedProjectOptions.GenerationOptions {
    static func from(
        manifest: ProjectDescription.Config.GenerationOptions,
        generatorPaths: GeneratorPaths
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
            optionalAuthentication: manifest.optionalAuthentication
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

extension TuistCore.TuistGeneratedProjectOptions.GenerationOptions.StaticSideEffectsWarningTargets {
    static func from(manifest: ProjectDescription.Config.GenerationOptions.StaticSideEffectsWarningTargets) -> Self {
        switch manifest {
        case .all: return .all
        case .none: return .none
        case let .excluding(excludedTargets): return .excluding(excludedTargets)
        }
    }
}
