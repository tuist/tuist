import Foundation
import TuistSupport

public struct TestingLogHandler: LogHandler {
    static var collected: [Logger.Level: [String]] {
        collectionQueue.sync {
            collectedLogs
        }
    }

    private static var collectionQueue = DispatchQueue(label: "io.tuist.tuistTestingSupport.logging")
    private static var collectedLogs: [Logger.Level: [String]] = [:]

    public var logLevel: Logger.Level
    public let label: String

    public init(label: String) {
        self.label = label
        logLevel = .trace
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata _: Logger.Metadata?,
        file _: String, function _: String, line _: UInt
    ) {
        TestingLogHandler.collectionQueue.async {
            TestingLogHandler.collectedLogs[level, default: []].append(message.description)
        }
    }

    public var metadata = Logger.Metadata()

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public static func reset() {
        TestingLogHandler.collectionQueue.async {
            TestingLogHandler.collectedLogs = [:]
        }
    }
}

extension Dictionary where Key == Logger.Level, Value == [String] {
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
