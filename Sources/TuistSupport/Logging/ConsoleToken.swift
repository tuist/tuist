/// A token used in the console to colourize output. This OptionSet is used to
/// allow for consumers to specify one-or-many different tokens to apply to the
/// formatting of a string rendered inside the console. See ColourizeSwift for
/// implementation details on how this unfolds when it arrives in Terminal.app.
public enum ConsoleToken: String {
    
    public static let key: String = "console-attributes"

    case white
    case green
    case red
    case cyan
    case yellow

    case bold
    
    var ƒ: (String) -> String {
        
        let function: (String) -> () -> String
        
        switch self {
        case .white:
            function = String.white
        case .green:
            function = String.green
        case .red:
            function = String.red
        case .cyan:
            function = String.cyan
        case .yellow:
            function = String.yellow
        case .bold:
            function = String.bold
        }
        
        return flip(function)()
        
    }

}

extension Set where Element == ConsoleToken {
    func apply(to string: String) -> String {
        reduce(string) { $1.ƒ($0) }
    }
}

extension String {
    func apply(_ token: Set<ConsoleToken>) -> String {
        token.apply(to: self)
    }
}

/// Provide API on anything `CustomStringConvertible` to allow for colouring inside the console
typealias Colorize = CustomStringConvertible

extension Colorize {
    
    public func cyan() -> Logger.Message {
        "\(description.cyan())"
    }
    
    public func red() -> Logger.Message {
        "\(description.red())"
    }
    
    public func blue() -> Logger.Message {
        "\(description.blue())"
    }
    
    public func green() -> Logger.Message {
        "\(description.green())"
    }
    
    public func yellow() -> Logger.Message {
        "\(description.yellow())"
    }
    
    public func bold() -> Logger.Message {
        "\(description.bold())"
    }
    
}

extension Colorize {
    
    public func section() -> Logger.Message {
        cyan().bold()
    }
    
    public func subsection() -> Logger.Message {
        cyan()
    }
    
    public func success() -> Logger.Message {
        green().bold()
    }
    
}

extension String.StringInterpolation {

    public mutating func appendInterpolation(_ value: String, _ token: ConsoleToken) {
        appendInterpolation(value, [ token ])
    }
    
    public mutating func appendInterpolation(_ value: String, _ token: Set<ConsoleToken>) {
        
        guard Environment.shared.shouldOutputBeColoured else {
            return appendLiteral(value)
        }
        
        appendLiteral(value.apply(token))

    }
    
}
