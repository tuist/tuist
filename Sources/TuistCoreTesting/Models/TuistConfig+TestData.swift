import Basic
import Foundation
@testable import TuistCore

public extension TuistConfig {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     generationOptions: [GenerationOption] = []) -> TuistConfig {
        return TuistConfig(compatibleXcodeVersions: compatibleXcodeVersions,
                           generationOptions: generationOptions)
    }
}
