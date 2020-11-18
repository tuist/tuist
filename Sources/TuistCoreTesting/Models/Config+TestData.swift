import Foundation
import TSCBasic
@testable import TuistCore

public extension Config {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     cloud: Cloud? = Cloud.test(),
                     generationOptions: [GenerationOption] = [],
                     path: AbsolutePath? = nil) -> Config
    {
        Config(compatibleXcodeVersions: compatibleXcodeVersions,
               cloud: cloud,
               generationOptions: generationOptions,
               path: path)
    }
}
