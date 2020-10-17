import TSCBasic
@testable import TuistDependencies

public final class MockDependenciesController: DependenciesControlling {
    public init() {}
    
    var fetchStub: ((AbsolutePath) throws -> Void)?
    public func fetch(at path: AbsolutePath) throws {
        try fetchStub?(path)
    }
    
    var updateStub: ((AbsolutePath) throws -> Void)?
    public func update(at path: AbsolutePath) throws {
        try updateStub?(path)
    }
}
