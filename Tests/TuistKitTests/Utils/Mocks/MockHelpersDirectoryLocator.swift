import Basic
import Foundation
@testable import TuistKit

final class MockHelpersDirectoryLocator: HelpersDirectoryLocating {
    var locateStub: AbsolutePath?
    var locateArgs: [AbsolutePath] = []

    func locate(at: AbsolutePath) -> AbsolutePath? {
        locateArgs.append(at)
        return locateStub
    }
}
