import Basic
import Foundation

public struct PrintableString: Encodable, Decodable, Equatable {
    /// Contains a string that can be interpolated with options.
    let rawString: String
}

extension PrintableString: ExpressibleByStringLiteral {
    public init(stringLiteral: String) {
        rawString = stringLiteral
    }
}

extension PrintableString: CustomStringConvertible {
    public var description: String {
        rawString
    }
}

extension PrintableString: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        rawString = stringInterpolation.string
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var string: String

        public init(literalCapacity _: Int, interpolationCount _: Int) {
            string = String()
        }

        public mutating func appendLiteral(_ literal: String) {
            string.append(literal)
        }

        public mutating func appendInterpolation(_ token: PrintableString.Token) {
            string.append(token.description)
        }

        public mutating func appendInterpolation(_ value: String) {
            string.append(value)
        }

        public mutating func appendInterpolation(_ value: CustomStringConvertible) {
            string.append(value.description)
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

        public var description: String {
            switch self {
            case let .raw(string):
                return string
            case let .command(token):
                return Environment.shared.shouldOutputBeColoured ? token.description.cyan() : token.description
            case let .keystroke(token):
                return Environment.shared.shouldOutputBeColoured ? token.description.cyan() : token.description
            case let .bold(token):
                return Environment.shared.shouldOutputBeColoured ? token.description.bold() : token.description
            case let .error(token):
                return Environment.shared.shouldOutputBeColoured ? token.description.red() : token.description
            case let .success(token):
                return Environment.shared.shouldOutputBeColoured ? token.description.green() : token.description
            case let .warning(token):
                return Environment.shared.shouldOutputBeColoured ? token.description.yellow() : token.description
            case let .info(token):
                return Environment.shared.shouldOutputBeColoured ? token.description.lightBlue() : token.description
            }
        }
    }
}

public protocol Printing: AnyObject {
    func print(_ text: PrintableString)
    func print(section: PrintableString)
    func print(subsection: PrintableString)
    func print(warning: PrintableString)
    func print(error: Error)
    func print(success: PrintableString)
    func print(errorMessage: PrintableString)
    func print(deprecation: PrintableString)
}

public class Printer: Printing {
    /// Shared instance
    public static var shared: Printing = Printer()

    // MARK: - Init

    init() {}

    // MARK: - Public

    public func print(_ text: PrintableString) {
        printStandardOutputLine(text.description)
    }

    public func print(error: Error) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardErrorLine("Error: \(error.localizedDescription)".localizedDescription.red().bold())
        } else {
            printStandardErrorLine("Error: \(error.localizedDescription)")
        }
    }

    public func print(success: PrintableString) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine("Success: \(success)".green().bold())
        } else {
            printStandardOutputLine("Success: \(success)")
        }
    }

    /// Prints a deprecation message (yellow color)
    ///
    /// - Parameter deprecation: Deprecation message.
    public func print(deprecation: PrintableString) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine("Deprecated: \(deprecation)".yellow().bold())
        } else {
            printStandardOutputLine("Deprecated: \(deprecation)")
        }
    }

    public func print(warning: PrintableString) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine("Warning: \(warning)".yellow().bold())
        } else {
            printStandardOutputLine("Warning: \(warning)")
        }
    }

    public func print(errorMessage: PrintableString) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardErrorLine("Error: \(errorMessage)".red().bold())
        } else {
            printStandardErrorLine("Error: \(errorMessage)")
        }
    }

    public func print(section: PrintableString) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine(section.description.cyan().bold())
        } else {
            printStandardOutputLine(section.description)
        }
    }

    public func print(subsection: PrintableString) {
        if Environment.shared.shouldOutputBeColoured {
            printStandardOutputLine(subsection.description.cyan())
        } else {
            printStandardOutputLine(subsection.description)
        }
    }

    // MARK: - Fileprivate

    fileprivate func printStandardOutputLine(_ string: String) {
        if let data = string.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }

    fileprivate func printStandardErrorLine(_ string: String) {
        if let data = string.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        FileHandle.standardError.write("\n".data(using: .utf8)!)
    }
}
