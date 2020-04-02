import Basic
import Foundation
import TuistSupport

public final class MockOpener: Opening {
    var openStub: Error?
    var openArgs: [(String, Bool)] = []
    var openCallCount: UInt = 0

    public func open(target: String, wait: Bool) throws {
        openCallCount += 1
        openArgs.append((target, wait))
        if let openStub = openStub { throw openStub }
    }

    public func open(path: AbsolutePath) throws {
        try open(target: path.pathString, wait: false)
    }

    public func open(url: URL) throws {
        try open(target: url.absoluteString, wait: false)
    }
}
