import Foundation
import Path
@testable import TuistLoader

final class MockProjectDescriptionHelpersHasher: ProjectDescriptionHelpersHashing {
    var stubHash: ((AbsolutePath) -> String)?
    func hash(helpersDirectory: AbsolutePath) throws -> String {
        stubHash?(helpersDirectory) ?? ""
    }
}
