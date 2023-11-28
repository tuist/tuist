import Foundation
import TuistSupport
import TuistSupportTesting

public struct AcceptanceTestCaseLogHandler: LogHandler {
    private let standardLogHandler: StandardLogHandler
    private let testingLogHandler: TestingLogHandler

    public init(label: String) {
        standardLogHandler = StandardLogHandler(label: label, logLevel: logLevel)
        testingLogHandler = TestingLogHandler(label: label)
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
        standardLogHandler.log(
            level: level,
            message: message,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
        testingLogHandler.log(
            level: level,
            message: message,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public var metadata = Logging.Logger.Metadata()
    public var logLevel: Logging.Logger.Level = .info
}
