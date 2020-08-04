import Foundation
import TSCBasic
@testable import TuistCore

public extension Config {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     scale: Scale? = Scale.test(),
                     generationOptions: [GenerationOption] = []) -> Config
    {
        Config(compatibleXcodeVersions: compatibleXcodeVersions,
               scale: scale,
               generationOptions: generationOptions)
    }
}
