import Foundation
import Logging

public struct JSONLogHandler: LogHandler {
    public var logLevel: Logger.Level

    public let label: String

    public init(label: String) {
        self.init(label: label, logLevel: .info)
    }

    public init(label: String, logLevel: Logger.Level) {
        self.label = label
        self.logLevel = logLevel
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        file _: String, function _: String, line _: UInt
    ) {
        let string: String

        switch metadata?[Logger.Metadata.tuist] {
        case Logger.Metadata.jsonKey?:
            string = message.description
        default:
            switch level {
            case .critical:
                if Environment.shared.shouldOutputBeColoured {
                    string = message.description.bold()
                } else {
                    string = message.description
                }
            case .error:
                if Environment.shared.shouldOutputBeColoured {
                    string = message.description.red()
                } else {
                    string = message.description
                }
            default:
                return
            }
        }

        output(for: level).print(string)
    }

    func output(for level: Logger.Level) -> FileHandle {
        level < .error ? .standardOutput : .standardError
    }

    public var metadata = Logger.Metadata()

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
}
