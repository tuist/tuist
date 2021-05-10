import TuistTasks
import TSCBasic

public final class MockTasksLocator: TasksLocating {
    public init() {}
    
    public var locateTasksStub: ((AbsolutePath) throws -> [AbsolutePath])?
    public func locateTasks(at path: AbsolutePath) throws -> [AbsolutePath] {
        try locateTasksStub?(path) ?? []
    }
}
