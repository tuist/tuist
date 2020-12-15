import Foundation
import TSCBasic
@testable import TuistCore

public extension Config {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     cloud: Cloud? = Cloud.test(),
                     plugins: [PluginLocation] = [],
                     generationOptions: [GenerationOption] = [],
                     path: AbsolutePath? = nil) -> Config
    {
        Config(compatibleXcodeVersions: compatibleXcodeVersions,
               cloud: cloud,
               plugins: plugins,
               generationOptions: generationOptions,
               path: path)
    }
}
