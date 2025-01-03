import ServiceContextModule
import Logging

private enum TestingLogHandlerServiceContextKey: ServiceContextKey {
    typealias Value = TestingLogHandler
}

extension ServiceContext {
    public var testingLogHandler: TestingLogHandler? {
        get {
            self[TestingLogHandlerServiceContextKey.self]
        } set {
            self[TestingLogHandlerServiceContextKey.self] = newValue
        }
    }
}

public extension ServiceContext {

    /// It uses service-context, which uses task locals (from structured concurrency), to inject
    /// instances of core utilities like logger to mock their behaviour for unit tests.
    /// 
    /// - Parameters:
    ///   - forwardLogs: When true, it forwards the logs through the standard output and error.
    ///   - closure: The closure that will be executed with the task-local context set.
    func withTestingDependencies(forwardLogs: Bool = false, _ closure: () async throws -> Void) async throws {
        var context = ServiceContext.topLevel
        let label = "dev.tuist.test"
        let testingLogHandler = TestingLogHandler(label: label, forwardLogs: forwardLogs)
        context.testingLogHandler = testingLogHandler
        context.logger = Logger(label: label, factory: { label in
            return testingLogHandler
        })
        try await ServiceContext.withValue(context) {
            try await closure()
        }
    }
    
}
