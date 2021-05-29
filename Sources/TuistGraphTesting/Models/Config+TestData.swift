import Foundation
import TSCBasic
@testable import TuistGraph

public extension Config {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     lab: Lab? = Lab.test(),
                     cache: Cache? = Cache.test(),
                     plugins: [PluginLocation] = [],
                     generationOptions: [GenerationOption] = [],
                     path: AbsolutePath? = nil) -> Config
    {
        Config(
            compatibleXcodeVersions: compatibleXcodeVersions,
            lab: lab,
            cache: cache,
            plugins: plugins,
            generationOptions: generationOptions,
            path: path
        )
    }
}
