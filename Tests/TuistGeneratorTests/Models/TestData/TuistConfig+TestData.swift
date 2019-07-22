import Basic
import Foundation
@testable import TuistGenerator

extension TuistConfig {
    static func test(generationOptions: [GenerationOption] = []) -> TuistConfig {
        return TuistConfig(generationOptions: generationOptions)
    }
}
