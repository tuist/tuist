import Basic
import Foundation
@testable import TuistCore

public extension TuistConfig {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     generationOptions: [GenerationOptions] = []) -> TuistConfig {
        TuistConfig(compatibleXcodeVersions: compatibleXcodeVersions,
                    generationOptions: generationOptions)
    }
}
