import Basic
import Foundation
@testable import TuistLoader

public final class MockRootDirectoryLocator: RootDirectoryLocating {
    public var locateArgs: [AbsolutePath] = []
    public var locateStub: AbsolutePath?

    public func locate(from path: AbsolutePath) -> AbsolutePath? {
        locateArgs.append(path)
        return locateStub
    }
}
