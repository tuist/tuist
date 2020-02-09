import Foundation
import Logging
import os

public struct OSLogHandler: LogHandler {
    
    public var logLevel: Logger.Level = .debug
    
    public let label: String
    private let os: OSLog
    
    public init(label: String) {
        self.label = label
        self.os = OSLog(subsystem: label, category: "")
    }
    
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        file: String, function: String, line: UInt
    ) {
        
        let metadataLog: String?
        
        if let metadata = metadata, !metadata.isEmpty {
            metadataLog = self.metadata.merging(metadata, uniquingKeysWith: { $1 }).pretty
        } else if !self.metadata.isEmpty {
            metadataLog = self.metadata.pretty
        } else {
            metadataLog = nil
        }

        os_log("%{public}@", log: os, type: .init(level: level), "\(timestamp()) \(level) \(URL(fileURLWithPath: file).lastPathComponent):\(line) \(message.description) \(metadataLog == nil ? "" : " -- \(metadataLog!)")")
    }

    public var metadata = Logger.Metadata()

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

}

extension Logger.Metadata {
    var pretty: String {
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
