import TSCBasic
import TuistSupport

public final class MockGitHandler: GitHandling {
    public init() {}

    public private(set) var cloneInCallCount = 0
    public private(set) var cloneInParameters: [(url: String, path: AbsolutePath)] = []
    public func clone(url: String, in path: AbsolutePath) throws {
        cloneInCallCount += 1
        cloneInParameters.append((url: url, path: path))
    }

    public private(set) var cloneToCallCount = 0
    public private(set) var cloneToParameters: [(url: String, path: AbsolutePath)] = []
    public func clone(url: String, to path: AbsolutePath) throws {
        cloneToCallCount += 1
        cloneToParameters.append((url: url, path: path))
    }

    public private(set) var checkoutCallCount = 0
    public private(set) var checkoutParameters: [(id: String, path: AbsolutePath)] = []
    public func checkout(id: String, in path: AbsolutePath) throws {
        checkoutCallCount += 1
        checkoutParameters.append((id: id, path: path))
    }
}
