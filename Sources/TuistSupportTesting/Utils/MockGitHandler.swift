import TSCBasic
import TSCUtility
import TuistSupport

/// A mock implementation of `GitHandling`.
public final class MockGitHandler: GitHandling {
    public init() {}

    public var cloneIntoStub: ((String, AbsolutePath) -> Void)?
    public func clone(url: String, into path: AbsolutePath) throws {
        cloneIntoStub?(url, path)
    }

    public var cloneToStub: ((String, AbsolutePath?) -> Void)?
    public func clone(url: String, to path: AbsolutePath?) throws {
        cloneToStub?(url, path)
    }

    public var checkoutStub: ((String, AbsolutePath?) -> Void)?
    public func checkout(id: String, in path: AbsolutePath?) throws {
        checkoutStub?(id, path)
    }

    public var remoteTaggedVersionsStub: [String]?
    public func remoteTaggedVersions(url _: String) -> [Version] {
        remoteTaggedVersionsStub?.compactMap { Version(string: $0) } ?? []
    }
}
