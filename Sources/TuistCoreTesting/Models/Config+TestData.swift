import Foundation
import TSCBasic
@testable import TuistCore

public extension Config {
    static func test(compatibleXcodeVersions: CompatibleXcodeVersions = .all,
                     cloudURL: URL? = nil,
                     generationOptions: [GenerationOption] = []) -> Config {
        Config(compatibleXcodeVersions: compatibleXcodeVersions,
               cloudURL: cloudURL,
               generationOptions: generationOptions)
    }
}
