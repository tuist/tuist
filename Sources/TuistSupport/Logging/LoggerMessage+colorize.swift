extension Logger.Message {
    
    func colorize(for logLevel: Logger.Level) -> Logger.Message {
        Logger.Message(stringLiteral: token(for: logLevel)?.apply(to: description) ?? description)
    }
    
    func token(for logLevel: Logger.Level) -> Set<ConsoleToken>? {
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
            return .none
        }
    }
    
}
