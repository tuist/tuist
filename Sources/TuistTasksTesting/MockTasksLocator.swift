import TuistTasks
import TSCBasic

public final class MockTasksLocator: TasksLocating {
    public init() {}
    
    public var locateTasks: ((AbsolutePath) throws -> [AbsolutePath])?
    public func locateTasks(at path: AbsolutePath) throws -> [AbsolutePath] {
        try locateTasks(at: path) ?? []
    }
}
