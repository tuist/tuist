import Foundation
import TuistSupport

public class TestingLogHandler: LogHandler {
    public var collected: [Logger.Level: [String]] {
        collectionQueue.sync {
            collectedLogs
        }
    }

    private var collectionQueue = DispatchQueue(label: "io.tuist.tuistTestingSupport.logging")
    private var collectedLogs: [Logger.Level: [String]] = [:]
    private let standardLogHandler: StandardLogHandler

    public var logLevel: Logger.Level
    public let label: String
    public let forwardLogs: Bool

    public init(label: String, forwardLogs: Bool) {
        self.label = label
        logLevel = .trace
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
