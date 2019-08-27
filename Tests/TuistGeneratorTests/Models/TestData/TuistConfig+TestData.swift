import Basic
import Foundation
@testable import TuistGenerator

extension TuistConfig {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     generationOptions: [GenerationOption] = []) -> TuistConfig {
        return TuistConfig(compatibleXcodeVersions: compatibleXcodeVersions,
                           generationOptions: generationOptions)
    }
}
