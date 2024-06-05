import Foundation
import TSCBasic
import TSCUtility
@testable import XcodeGraph

extension Config {
    public static func test(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        cloud: Cloud? = Cloud.test(),
        swiftVersion: Version? = nil,
        plugins: [PluginLocation] = [],
        generationOptions: GenerationOptions = Config.default.generationOptions,
        path: AbsolutePath? = nil
    ) -> Config {
        .init(
            compatibleXcodeVersions: compatibleXcodeVersions,
            cloud: cloud,
            swiftVersion: swiftVersion,
            plugins: plugins,
            generationOptions: generationOptions,
            path: path
        )
    }
}

extension Config.GenerationOptions {
    public static func test(
        resolveDependenciesWithSystemScm: Bool = false,
        disablePackageVersionLocking: Bool = false,
        clonedSourcePackagesDirPath: AbsolutePath? = nil,
        staticSideEffectsWarningTargets: XcodeGraph.Config.GenerationOptions.StaticSideEffectsWarningTargets = .all,
        enforceExplicitDependencies: Bool = false,
        defaultConfiguration: String? = nil
    ) -> Self {
        .init(
            resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
            disablePackageVersionLocking: disablePackageVersionLocking,
            clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
            staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
            enforceExplicitDependencies: enforceExplicitDependencies,
            defaultConfiguration: defaultConfiguration
        )
    }
}
