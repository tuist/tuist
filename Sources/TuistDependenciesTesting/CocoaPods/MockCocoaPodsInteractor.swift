import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    public init() {}

    var invokedFetch = false
    var fetchStub: ((AbsolutePath) throws -> Void)?

    public func fetch(dependenciesDirectory: AbsolutePath) throws {
        invokedFetch = true
        try fetchStub?(dependenciesDirectory)
    }

    var invokedUpdate = false
    var updateStub: ((AbsolutePath) throws -> Void)?

    public func update(dependenciesDirectory: AbsolutePath) throws {
        invokedUpdate = true
        try updateStub?(dependenciesDirectory)
    }
}
