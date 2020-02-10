import Foundation
import Logging

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
        file: String, function: String, line: UInt
    ) {

        let log: Logger.Message
        
        if Environment.shared.shouldOutputBeColoured {
            log = message.colorize(for: level)
        } else {
            log = message
        }

        output(for: level).print(log.description)

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

extension Logger.Message {
    
    func colorize(for logLevel: Logger.Level) -> Logger.Message {
        Logger.Message(stringLiteral: token(for: logLevel).apply(to: description))
    }
    
    func token(for logLevel: Logger.Level) -> Set<ConsoleToken> {
        switch logLevel {
        case .critical:
            return [ .red, .bold ]
        case .error:
            return [ .red ]
        case .warning:
            return [ .yellow ]
        case .notice:
            return [ .bold ]
        case .debug, .trace, .info:
            return .init()
        }
    }
    
}
