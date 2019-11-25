import Basic
import Foundation
import TuistSupport

public final class MockOpener: Opening {
    var openStub: Error?
    var openArgs: [(AbsolutePath, Bool)] = []
    var openCallCount: UInt = 0

    public func open(path: AbsolutePath, wait: Bool) throws {
        openCallCount += 1
        openArgs.append((path, wait))
        if let openStub = openStub { throw openStub }
    }

    public func open(path: AbsolutePath) throws {
        try open(path: path, wait: true)
    }
}
