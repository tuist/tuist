import Basic
import Foundation
import TuistSupport

public final class MockOpener: Opening {
    var openStub: Error?
    var openArgs: [AbsolutePath] = []
    var openCallCount: UInt = 0

    public func open(path: AbsolutePath) throws {
        openCallCount += 1
        openArgs.append(path)
        if let openStub = openStub { throw openStub }
    }
}
