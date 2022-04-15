import Foundation
import Logging

public struct DetailedLogHandler: LogHandler {
    public let label: String

    private var stdout: LogHandler
    private var stderr: LogHandler

    public init(label: String) {
        self.init(label: label, logLevel: .info)
    }

    public init(label: String, logLevel: Logger.Level) {
        self.label = label
        stdout = StreamLogHandler.standardOutput(label: label)
        stdout.logLevel = logLevel
        stderr = StreamLogHandler.standardOutput(label: label)
        stderr.logLevel = logLevel
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        file: String, function: String, line: UInt
    ) {
        var log = "\(timestamp()) \(level.rawValue) \(label)"

        let mergedMetadata = metadata.map { self.metadata.merging($0, uniquingKeysWith: { $1 }) } ?? self.metadata

        if mergedMetadata.isNotEmpty {
            log.append(mergedMetadata.prettyDescription)
        }

        log.append(message.description)

        (output(for: level) as? SuppressedWarningLogHandler)?
            .log(level: level, message: message, metadata: metadata, file: file, function: function, line: line)
    }

    func output(for level: Logger.Level) -> LogHandler {
        level < .error ? stdout : stderr
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public var metadata: Logger.Metadata = .init()

    public var logLevel: Logger.Level {
        get { stdout.logLevel }
        set {
            stdout.logLevel = newValue
            stderr.logLevel = newValue
        }
    }
}

extension Collection {
    var isNotEmpty: Bool { !isEmpty }
}

func timestamp() -> String {
    var buffer = [Int8](repeating: 0, count: 255)
    var timestamp = time(nil)
    let localTime = localtime(&timestamp)
    strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
    return buffer.withUnsafeBufferPointer {
        $0.withMemoryRebound(to: CChar.self) {
            String(cString: $0.baseAddress!)
        }
    }
}

// Protocol needed to suppress the warning because we don't have a valid `source` to pass to the `log` method
protocol SuppressedWarningLogHandler {
    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        file: String,
        function: String,
        line: UInt
    )
}

extension StreamLogHandler: SuppressedWarningLogHandler {}
