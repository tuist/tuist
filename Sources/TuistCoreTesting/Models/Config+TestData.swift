import Basic
import Foundation
@testable import TuistCore

public extension Config {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     generationOptions: [GenerationOption] = []) -> Config {
        Config(compatibleXcodeVersions: compatibleXcodeVersions,
               generationOptions: generationOptions)
    }
}
