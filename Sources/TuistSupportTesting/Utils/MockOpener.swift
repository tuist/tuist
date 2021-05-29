import Foundation
import TSCBasic
import TuistSupport

// swiftlint:disable large_tuple

public final class MockOpener: Opening {
    var openStub: Error?
    var openArgs: [(String, Bool, AbsolutePath?)] = []
    var openCallCount: UInt = 0

    public func open(target: String, wait: Bool) throws {
        openCallCount += 1
        openArgs.append((target, wait, nil))
        if let openStub = openStub { throw openStub }
    }

    public func open(path: AbsolutePath, wait: Bool) throws {
        try open(target: path.pathString, wait: wait)
    }

    public func open(path: AbsolutePath) throws {
        try open(target: path.pathString, wait: false)
    }

    public func open(url: URL) throws {
        try open(target: url.absoluteString, wait: false)
    }

    public func open(path: AbsolutePath, application: AbsolutePath) throws {
        try open(path: path, application: application, wait: true)
    }

    public func open(path: AbsolutePath, application: AbsolutePath, wait _: Bool) throws {
        openCallCount += 1
        openArgs.append((path.pathString, false, application))
        if let openStub = openStub { throw openStub }
    }
}

// swiftlint:enable large_tuple
