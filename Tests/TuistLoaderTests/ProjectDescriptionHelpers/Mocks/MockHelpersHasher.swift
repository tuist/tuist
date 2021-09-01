import Foundation
import TSCBasic
@testable import TuistLoader

final class MockHelpersHasher: HelpersHashing {
    var stubHash: ((AbsolutePath) -> String)?
    func hash(helpersDirectory: AbsolutePath) throws -> String {
        stubHash?(helpersDirectory) ?? ""
    }

    var stubPrefixHash: ((AbsolutePath) -> String)?
    func prefixHash(helpersDirectory: AbsolutePath) -> String {
        stubPrefixHash?(helpersDirectory) ?? ""
    }
}
