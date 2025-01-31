import Foundation
import Logging
import ServiceContextModule
import Noora

public struct StandardLogHandler: LogHandler {
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
        if let metadata, metadata[Logger.Metadata.tuist] == .string(Logger.Metadata.prettyKey) {
            return
        }

        let string: String

        if Environment.shared.shouldOutputBeColoured {
            switch metadata?[Logger.Metadata.tuist] {
            case Logger.Metadata.successKey?:
                string = message.description.green().bold()
            case Logger.Metadata.sectionKey?:
                string = message.description.cyan().bold()
            case Logger.Metadata.subsectionKey?:
                string = message.description.cyan()
            default:
                switch level {
                case .critical:
                    string = message.description.red().bold()
                case .error:
                    string = message.description.red()
                case .warning:
                    ServiceContext.current?.alerts?.append(.warning(.alert("\(message.description)")))
                    return
                case .notice, .info, .debug, .trace:
                    string = message.description
                }
            }
        } else {
            string = message.description
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

extension FileHandle {
    func print(_ string: String, terminator: String = "\n") {
        (string + terminator).data(using: .utf8)
            .map(write)
    }
}

func ~= (lhs: String, rhs: Logger.MetadataValue) -> Bool {
    switch rhs {
    case let .string(s): return lhs == s
    default: return false
    }
}
