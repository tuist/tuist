import TSCBasic
import TuistCore

@testable import TuistDependencies

public final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    public init() {}

    var invokedInstall = false
    var installStub: ((AbsolutePath, Bool) throws -> Void)?

    public func install(
        dependenciesDirectory: AbsolutePath,
        shouldUpdate: Bool
    ) throws {
        invokedInstall = true
        try installStub?(dependenciesDirectory, shouldUpdate)
    }

    var invokedClean = false
    var cleanStub: ((AbsolutePath) throws -> Void)?

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        invokedClean = true
        try cleanStub?(dependenciesDirectory)
    }
}
