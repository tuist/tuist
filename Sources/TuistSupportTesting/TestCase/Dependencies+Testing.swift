import Logging
import Noora
import Testing
import TuistSupport

/// It uses service-context, which uses task locals (from structured concurrency), to inject
/// instances of core utilities like logger to mock their behaviour for unit tests.
///
/// - Parameters:
///   - forwardLogs: When true, it forwards the logs through the standard output and error.
///   - closure: The closure that will be executed with the task-local context set.
public func withTestingDependencies(forwardLogs _: Bool = false, _ closure: () async throws -> Void) async throws {
    let (logger, logHandler) = Logger.initTestingLogger()

    try await Logger.$current.withValue(logger) {
        try await Logger.$testingLogHandler.withValue(logHandler) {
            try await Noora.$current.withValue(NooraMock(terminal: Terminal(isInteractive: false))) {
                try await RecentPathsStore.$current.withValue(MockRecentPathsStoring()) {
                    try await AlertController.$current.withValue(AlertController()) {
                        try await closure()
                    }
                }
            }
        }
    }
}

public func withMockedDeveloperEnvironment(_ closure: () async throws -> Void) async throws {
    try await DeveloperEnvironment.$current.withValue(MockDeveloperEnvironment()) {
        try await closure()
    }
}

public func withMockedEnvironment(_ closure: () async throws -> Void) async throws {
    try await Environment.$current.withValue(MockEnvironment()) {
        try await closure()
    }
}

public func expectLogs(
    _ expected: String,
    at level: Logger.Level = .warning,
    _ comparison: (Logger.Level, Logger.Level) -> Bool = { $0 >= $1 },
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let output = Logger.testingLogHandler.collected[level, comparison]
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

public func doesntExpectLogs(_ pattern: String) {
    let standardOutput = Logger.testingLogHandler.collected[.info, <=]

    let message = """
    The standard output:
    ===========
    \(standardOutput)

    Contains the not expected:
    ===========
    \(pattern)
    """

    #expect(standardOutput.contains(pattern) == false)
}
