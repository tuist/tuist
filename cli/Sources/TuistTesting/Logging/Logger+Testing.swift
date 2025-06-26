import Foundation
import Logging
import Testing
import TuistSupport

public class TestingLogHandler: LogHandler {
    public var collected: [Logger.Level: [String]] {
        collectionQueue.sync {
            collectedLogs
        }
    }

    private var collectionQueue = DispatchQueue(label: "dev.tuist.tuistTestingSupport.logging")
    private var collectedLogs: [Logger.Level: [String]] = [:]
    private let standardLogHandler: StandardLogHandler

    public var logLevel: Logger.Level
    public let label: String
    public let forwardLogs: Bool

    public init(label: String, forwardLogs: Bool) {
        self.label = label
        logLevel = Environment.current.isVerbose ? .trace : .info
        standardLogHandler = StandardLogHandler(label: label, logLevel: logLevel)
        self.forwardLogs = forwardLogs
    }

    public func flush() {
        collectionQueue.async {
            self.collectedLogs = [:]
        }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source _: String,
        file: String,
        function: String,
        line: UInt
    ) {
        if forwardLogs {
            standardLogHandler.log(
                level: level,
                message: message,
                metadata: metadata,
                file: file,
                function: function,
                line: line
            )
        }
        collectionQueue.async {
            self.collectedLogs[level, default: []].append(message.description)
        }
    }

    public var metadata = Logger.Metadata()

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
}

extension [Logger.Level: [String]] {
    public subscript(_ key: Key, _ comparison: (Key, Key) -> Bool) -> String {
        let level = [Key](repeating: key, count: keys.count)
        return Swift.zip(level, keys)
            .lazy
            .filter(comparison)
            .compactMap { self[$1] }
            .joined()
            .joined(separator: "\n")
    }
}

extension Logger {
    private static var label = "dev.tuist.test"
    @TaskLocal public static var testingLogHandler: TestingLogHandler = .init(label: Self.label, forwardLogs: false)

    public static func initTestingLogger(forwardLogs: Bool = false) -> (logger: Self, handler: TestingLogHandler) {
        let label = Self.label
        let testingLogHandler = TestingLogHandler(label: Self.label, forwardLogs: forwardLogs)
        return (logger: Logger(label: label, factory: { _ in testingLogHandler }), handler: testingLogHandler)
    }
}

public struct LoggerTestingTrait: TestTrait, SuiteTrait, TestScoping {
    let forwardLogs: Bool

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let (logger, handler) = Logger.initTestingLogger(forwardLogs: forwardLogs)
        try await Logger.$current.withValue(logger) {
            try await Logger.$testingLogHandler.withValue(handler) {
                try await function()
            }
        }
    }
}

extension Trait where Self == LoggerTestingTrait {
    /// When this trait is applied, it uses a mock for the task local `Logger.current`.`
    public static func withMockedLogger(forwardLogs: Bool = false) -> Self {
        return Self(forwardLogs: forwardLogs)
    }
}
