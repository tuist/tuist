import Foundation
import TSCBasic
@testable import TuistCore

public extension Config {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     cloud: Cloud? = Cloud.test(),
                     generationOptions: [GenerationOption] = []) -> Config
    {
        Config(compatibleXcodeVersions: compatibleXcodeVersions,
               cloud: cloud,
               generationOptions: generationOptions)
    }
}
