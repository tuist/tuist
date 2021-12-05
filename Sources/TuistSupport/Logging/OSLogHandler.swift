import Foundation
import struct Logging.Logger
import os

public struct OSLogHandler: LogHandler {
    public var logLevel: Logger.Level

    public let label: String
    private let os: OSLog

    public init(label: String) {
        self.init(label: label, logLevel: .info)
    }

    public init(label: String, logLevel: Logger.Level) {
        self.label = label
        self.logLevel = logLevel
        os = OSLog(subsystem: label, category: "")
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        file: String, function _: String, line: UInt
    ) {
        let metadataLog: String?

        if let metadata = metadata, !metadata.isEmpty {
            metadataLog = self.metadata.merging(metadata, uniquingKeysWith: { $1 }).prettyDescription
        } else if !self.metadata.isEmpty {
            metadataLog = self.metadata.prettyDescription
        } else {
            metadataLog = nil
        }

        os_log(
            "%{public}@",
            log: os,
            type: .init(level: level),
            "\(timestamp()) \(level) \(URL(fileURLWithPath: file).lastPathComponent):\(line) \(message.description) \(metadataLog == nil ? "" : " -- \(metadataLog!)")"
        )
    }

    public var metadata = Logger.Metadata()

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
}

extension Logger.Metadata {
    var prettyDescription: String {
        map { "\($0)=\($1)" }.joined(separator: " ")
    }
}

extension OSLogType {
    init(level: Logger.Level) {
        switch level {
        case .trace:
            self = .debug
        case .debug:
            self = .debug
        case .info:
            self = .info
        case .notice:
            self = .info
        case .warning:
            self = .info
        case .error:
            self = .error
        case .critical:
            self = .fault
        }
    }
}
