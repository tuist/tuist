import TSCBasic
import TuistSupport

/// A mock implementation of `GitHandling`.
public final class MockGitHandler: GitHandling {
    public init() {}

    public private(set) var cloneIntoStub: ((String, AbsolutePath) -> Void)?
    public func clone(url: String, into path: AbsolutePath) throws {
        cloneIntoStub?(url, path)
    }

    public private(set) var cloneToStub: ((String, AbsolutePath?) -> Void)?
    public func clone(url: String, to path: AbsolutePath?) throws {
        cloneToStub?(url, path)
    }

    public private(set) var checkoutStub: ((String, AbsolutePath?) -> Void)?
    public func checkout(id: String, in path: AbsolutePath?) throws {
        checkoutStub?(id, path)
    }
}
