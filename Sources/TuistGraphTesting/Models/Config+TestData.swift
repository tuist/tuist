import Foundation
import TSCBasic
import TSCUtility
@testable import TuistGraph

public extension Config {
    static func test(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        cloud: Cloud? = Cloud.test(),
        cache: Cache? = Cache.test(),
        swiftVersion: Version? = nil,
        plugins: [PluginLocation] = [],
        generationOptions: [GenerationOption] = [],
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
