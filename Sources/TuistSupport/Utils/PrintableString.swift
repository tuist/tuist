import Foundation

public struct PrintableString: Encodable, Decodable, Equatable {
    /// Contains a string that can be interpolated with options.
    let rawString: String
    let pretty: String
}

extension PrintableString: ExpressibleByStringLiteral {
    public init(stringLiteral: String) {
        rawString = stringLiteral
        pretty = stringLiteral
    }
}

extension PrintableString: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        pretty
    }

    public var debugDescription: String {
        rawString
    }
}

extension PrintableString: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        rawString = stringInterpolation.unformatted
        pretty = stringInterpolation.string
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var unformatted: String
        var string: String

        public init(literalCapacity _: Int, interpolationCount _: Int) {
            string = ""
            unformatted = ""
        }

        public mutating func appendLiteral(_ literal: String) {
            string.append(literal)
            unformatted.append(literal)
        }

        public mutating func appendInterpolation(_ token: PrintableString.Token) {
            string.append(token.description)
            unformatted.append(token.unformatted)
        }

        public mutating func appendInterpolation(_ value: String) {
            string.append(value)
            unformatted.append(value)
        }

        public mutating func appendInterpolation(_ value: CustomStringConvertible) {
            string.append(value.description)
            unformatted.append(value.description)
        }
    }
}

extension PrintableString {
    public indirect enum Token: ExpressibleByStringLiteral {
        case raw(String)
        case command(Token)
        case keystroke(Token)
        case bold(Token)
        case error(Token)
        case success(Token)
        case warning(Token)
        case info(Token)

        public init(stringLiteral: String) {
            self = .raw(stringLiteral)
        }

        public var unformatted: String {
            switch self {
            case let .raw(string):
                return string
            case let .command(token):
                return token.description
            case let .keystroke(token):
                return token.description
            case let .bold(token):
                return token.description
            case let .error(token):
                return token.description
            case let .success(token):
                return token.description
            case let .warning(token):
                return token.description
            case let .info(token):
                return token.description
            }
        }

        public var description: String {
            guard Environment.shared.shouldOutputBeColoured else {
                return unformatted
            }

            switch self {
            case let .raw(string):
                return string
            case let .command(token), let .keystroke(token):
                return token.description.cyan()
            case let .bold(token):
                return token.description.bold()
            case let .error(token):
                return token.description.red()
            case let .success(token):
                return token.description.green()
            case let .warning(token):
                return token.description.yellow()
            case let .info(token):
                return token.description.lightBlue()
            }
        }
    }
}

extension Logger {
    /// Log a message passing with the `Logger.Level.notice` log level.
    ///
    /// `pretty` is always printed to the console, and is omitted to the logger as `notice`.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#file`).
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    public func pretty(
        _ message: @autoclosure () -> PrintableString,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        file: String = #file, function: String = #function, line: UInt = #line
    ) {
        let printableString = message()

        log(
            level: .notice, Logger.Message(stringLiteral: printableString.rawString),
            metadata: metadata().map { $0.merging(.pretty, uniquingKeysWith: { $1 }) } ?? .pretty,
            file: file,
            function: function,
            line: line
        )

        if Environment.shared.shouldOutputBeColoured {
            FileHandle.standardOutput.print(printableString.pretty)
        } else {
            FileHandle.standardOutput.print(printableString.rawString)
        }
    }
}
