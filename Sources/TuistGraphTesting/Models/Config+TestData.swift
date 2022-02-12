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
        resolveDependenciesWithSystemScm: Bool = false,
        disablePackageVersionLocking: Bool = false
    ) -> Self {
        .init(
            resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
            disablePackageVersionLocking: disablePackageVersionLocking
        )
    }
}
