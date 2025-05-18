import Logging
import Noora
import ServiceContextModule
import Testing
import TuistSupport

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

extension ServiceContext {
    /// It uses service-context, which uses task locals (from structured concurrency), to inject
    /// instances of core utilities like logger to mock their behaviour for unit tests.
    ///
    /// - Parameters:
    ///   - forwardLogs: When true, it forwards the logs through the standard output and error.
    ///   - closure: The closure that will be executed with the task-local context set.
    public static func withTestingDependencies(forwardLogs: Bool = false, _ closure: () async throws -> Void) async throws {
        var context = ServiceContext.topLevel
        let label = "dev.tuist.test"
        let testingLogHandler = TestingLogHandler(label: label, forwardLogs: forwardLogs)
        context.testingLogHandler = testingLogHandler
        context.logger = Logger(label: label, factory: { _ in
            return testingLogHandler
        })

        context.recentPaths = MockRecentPathsStoring()

        try await Noora.$current.withValue(NooraMock(terminal: Terminal(isInteractive: false))) {
            try await AlertController.$current.withValue(AlertController()) {
                try await ServiceContext.withValue(context) {
                    try await closure()
                }
            }
        }
    }

    public static func expectLogs(
        _ expected: String,
        at level: Logger.Level = .warning,
        _ comparison: (Logger.Level, Logger.Level) -> Bool = { $0 >= $1 },
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let testingLogHandler = try #require(
            ServiceContext.current?.testingLogHandler,
            "The testing log handler hasn't been set with ServiceContext.withTestingDependencies."
        )
        let output = testingLogHandler.collected[level, comparison]
        let message = """
        The output:
        ===========
        \(output)

        Doesn't contain the expected:
        ===========
        \(expected)
        """
        #expect(output.contains(expected) == true, "\(message)", sourceLocation: sourceLocation)
    }
}
