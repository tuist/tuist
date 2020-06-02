import Foundation
import TSCBasic
@testable import TuistLoader

final class MockProjectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing {
    var stubHash: ((AbsolutePath) -> String)?
    func hash(helpersDirectory: AbsolutePath) throws -> String {
        stubHash?(helpersDirectory) ?? ""
    }

    var stubPrefixHash: ((AbsolutePath) -> String)?
    func prefixHash(helpersDirectory: AbsolutePath) -> String {
        stubPrefixHash?(helpersDirectory) ?? ""
    }
}
