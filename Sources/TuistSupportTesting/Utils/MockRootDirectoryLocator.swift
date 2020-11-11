import Foundation
import TSCBasic

@testable import TuistSupport

public final class MockRootDirectoryLocator: RootDirectoryLocating {
    public var locateArgs: [AbsolutePath] = []
    public var locateStub: AbsolutePath?

    public func locate(from path: AbsolutePath) -> AbsolutePath? {
        locateArgs.append(path)
        return locateStub
    }
}
