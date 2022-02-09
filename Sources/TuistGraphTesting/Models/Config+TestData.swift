import Foundation
import TSCBasic
import TSCUtility
@testable import TuistGraph

extension Config {
    public static func test(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        cloud: Cloud? = Cloud.test(),
        cache: Cache? = Cache.test(),
        swiftVersion: Version? = nil,
        plugins: [PluginLocation] = [],
        generationOptions: GenerationOptions = Config.default.generationOptions,
        path: AbsolutePath? = nil
    ) -> Config {
        .init(
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

extension Config.GenerationOptions {
    public static func test(
        xcodeProjectName: String? = nil,
        organizationName: String? = nil,
        developmentRegion: String? = nil,
        disableShowEnvironmentVarsInScriptPhases: Bool = false,
        templateMacros: IDETemplateMacros? = nil,
        resolveDependenciesWithSystemScm: Bool = false,
        disablePackageVersionLocking: Bool = false,
        lastXcodeUpgradeCheck: Version? = nil
    ) -> Self {
        .init(
            xcodeProjectName: xcodeProjectName,
            organizationName: organizationName,
            developmentRegion: developmentRegion,
            disableShowEnvironmentVarsInScriptPhases: disableShowEnvironmentVarsInScriptPhases,
            templateMacros: templateMacros,
            resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
            disablePackageVersionLocking: disablePackageVersionLocking,
            lastXcodeUpgradeCheck: lastXcodeUpgradeCheck
        )
    }
}
