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
            
            switch metadata?[Logger.Metadata.colored] {
            case .string(Logger.Metadata.successKey)?:
                log = Logger.Message(stringLiteral: message.description.apply([ .green, .bold ]))
            case .string(Logger.Metadata.sectionKey)?:
                log = Logger.Message(stringLiteral: message.description.apply([ .cyan, .bold ]))
            case .string(Logger.Metadata.subsectionKey)?:
                log = Logger.Message(stringLiteral: message.description.apply([ .cyan ]))
            default:
                log = message.colorize(for: level)
            }
            
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

extension FileHandle {
    
    func print(_ string: String, terminator: String = "\n") {
        string.data(using: .utf8)
            .map(write)
        terminator.data(using: .utf8)
            .map(write)
    }
    
}
