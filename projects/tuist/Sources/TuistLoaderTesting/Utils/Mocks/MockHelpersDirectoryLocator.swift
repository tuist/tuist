import Foundation
import TSCBasic
@testable import TuistLoader

public final class MockHelpersDirectoryLocator: HelpersDirectoryLocating {
    public var locateStub: AbsolutePath?
    public var locateArgs: [AbsolutePath] = []

    public func locate(at: AbsolutePath) -> AbsolutePath? {
        locateArgs.append(at)
        return locateStub
    }
}
