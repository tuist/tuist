import Foundation
import TSCBasic
@testable import TuistGraph

public extension Config {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     cloud: Cloud? = Cloud.test(),
                     cache: Cache? = Cache.test(),
                     swiftToolsVersion: String? = nil,
                     plugins: [PluginLocation] = [],
                     generationOptions: [GenerationOption] = [],
                     path: AbsolutePath? = nil) -> Config
    {
        Config(
            compatibleXcodeVersions: compatibleXcodeVersions,
            cloud: cloud,
            cache: cache,
            swiftToolsVersion: swiftToolsVersion,
            plugins: plugins,
            generationOptions: generationOptions,
            path: path
        )
    }
}
