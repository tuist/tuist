import Basic
import Foundation
@testable import TuistKit

final class MockRootDirectoryLocator: RootDirectoryLocating {
    var locateArgs: [AbsolutePath] = []
    var locateStub: AbsolutePath?

    func locate(from path: AbsolutePath) -> AbsolutePath? {
        locateArgs.append(path)
        return locateStub
    }
}
