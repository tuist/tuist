import Foundation
import TSCBasic
@testable import TuistCore

public final class MockRootDirectoryLocator: RootDirectoryLocating {
    public var locateArgs: [AbsolutePath] = []
    public var locateStub: AbsolutePath?
    public var usingProjectManifest: Bool

    public init(usingProjectManifest: Bool) {
        self.usingProjectManifest = usingProjectManifest
    }

    public func locate(from path: AbsolutePath) -> AbsolutePath? {
        locateArgs.append(path)
        return locateStub
    }
}
