public enum ConsolePrettyToken: String {
    
    case highlight
    case command
    case keystroke
    
    var tokens: Set<ConsoleToken> {
        switch self {
        case .highlight:
            return [ .bold ]
        case .command:
            return [ .white, .bold ]
        case .keystroke:
            return [ .cyan ]
        }
    }
    
}

extension Logger.Metadata {
    
    public static let colored: String = "is"
    
    public static let successKey: String = "success"
    public static var success: Logger.Metadata {
        return [ colored: .string(successKey) ]
    }
    
    public static let sectionKey: String = "section"
    public static var section: Logger.Metadata {
        return [ colored: .string(sectionKey) ]
    }
    
    public static let subsectionKey: String = "subsection"
    public static var subsection: Logger.Metadata {
        return [ colored: .string(subsectionKey) ]
    }
    
}

extension String.StringInterpolation {

    public mutating func appendInterpolation(_ value: String, _ first: ConsolePrettyToken, rest: ConsolePrettyToken...) {
        appendInterpolation(value, [ first ] + rest)
    }
    
    public mutating func appendInterpolation(_ value: String, _ token: [ConsolePrettyToken]) {
        let tokens = token.flatMap({ $0.tokens })
        appendInterpolation(value, Set(tokens))
    }
    
    internal mutating func appendInterpolation(_ value: String, _ token: Set<ConsoleToken>) {
        
        if Environment.shared.shouldOutputBeColoured {
            appendLiteral(value.apply(token))
        } else {
            appendLiteral(value)
        }

    }
    
}

extension Set where Element == ConsoleToken {
    func apply(to string: String) -> String {
        reduce(string) { $1.apply($0) }
    }
}

extension String {
    func apply(_ token: Set<ConsoleToken>) -> String {
        token.apply(to: self)
    }
}

/// A token used in the console to colourize output. This OptionSet is used to
/// allow for consumers to specify one-or-many different tokens to apply to the
/// formatting of a string rendered inside the console. See ColourizeSwift for
/// implementation details on how this unfolds when it arrives in Terminal.app.
enum ConsoleToken: String {
    case black
    case blue
    case cyan
    case darkGray
    case green
    case lightBlue
    case lightCyan
    case lightGray
    case lightGreen
    case lightMagenta
    case lightRed
    case lightYellow
    case magenta
    case onBlack
    case onBlue
    case onCyan
    case onDarkGray
    case onGreen
    case onLightBlue
    case onLightCyan
    case onLightGray
    case onLightGreen
    case onLightMagenta
    case onLightRed
    case onLightYellow
    case onMagenta
    case onRed
    case onWhite
    case onYellow
    case red
    case white
    case yellow

    case blink
    case bold
    case dim
    case hidden
    case italic
    case reset
    case reverse
    case strikethrough
    case underline
    
    var apply: (String) -> String {
        
        let ƒ: (String) -> () -> String
        
        switch self {
        case .black:
            ƒ = String.black
        case .blue:
            ƒ = String.blue
        case .cyan:
            ƒ = String.cyan
        case .darkGray:
            ƒ = String.darkGray
        case .green:
            ƒ = String.green
        case .lightBlue:
            ƒ = String.lightBlue
        case .lightCyan:
            ƒ = String.lightCyan
        case .lightGray:
            ƒ = String.lightGray
        case .lightGreen:
            ƒ = String.lightGreen
        case .lightMagenta:
            ƒ = String.lightMagenta
        case .lightRed:
            ƒ = String.lightRed
        case .lightYellow:
            ƒ = String.lightYellow
        case .magenta:
            ƒ = String.magenta
        case .onBlack:
            ƒ = String.onBlack
        case .onBlue:
            ƒ = String.onBlue
        case .onCyan:
            ƒ = String.onCyan
        case .onDarkGray:
            ƒ = String.onDarkGray
        case .onGreen:
            ƒ = String.onGreen
        case .onLightBlue:
            ƒ = String.onLightBlue
        case .onLightCyan:
            ƒ = String.onLightCyan
        case .onLightGray:
            ƒ = String.onLightGray
        case .onLightGreen:
            ƒ = String.onLightGreen
        case .onLightMagenta:
            ƒ = String.onLightMagenta
        case .onLightRed:
            ƒ = String.onLightRed
        case .onLightYellow:
            ƒ = String.onLightYellow
        case .onMagenta:
            ƒ = String.onMagenta
        case .onRed:
            ƒ = String.onRed
        case .onWhite:
            ƒ = String.onWhite
        case .onYellow:
            ƒ = String.onYellow
        case .red:
            ƒ = String.red
        case .white:
            ƒ = String.white
        case .yellow:
            ƒ = String.yellow
            
        case .bold:
            ƒ = String.bold
        case .dim:
            ƒ = String.dim
        case .italic:
            ƒ = String.italic
        case .underline:
            ƒ = String.underline
        case .blink:
            ƒ = String.blink
        case .reverse:
            ƒ = String.reverse
        case .hidden:
            ƒ = String.hidden
        case .strikethrough:
            ƒ = String.strikethrough
        case .reset:
            ƒ = String.reset
        }
        
        return flip(ƒ)()
        
    }

}
