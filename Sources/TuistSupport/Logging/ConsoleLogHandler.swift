import Foundation
import Logging

public struct ConsoleLogHandler: LogHandler {
    
    public let label: String
    
    public static func verbose(label: String) -> LogHandler {
        ConsoleLogHandler(label: label, level: .debug)
    }
    
    private var stdout: LogHandler
    private var stderr: LogHandler
    
    public init(label: String) {
        self.init(label: label, level: .info)
    }
    
    public init(label: String, level: Logger.Level) {
        self.label = label
        stdout = StreamLogHandler.standardOutput(label: label)
        stdout.logLevel = level
        stderr = StreamLogHandler.standardOutput(label: label)
        stderr.logLevel = level
    }
    
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        file: String, function: String, line: UInt
    ) {

        let attributes: ConsoleToken
        
        switch level {
        case .critical:
            attributes = [ .red, .bold ]
        case .error:
            attributes = [ .red ]
        case .warning:
            attributes = [ .yellow ]
        case .notice:
            attributes = [ .bold ]
        case .debug, .trace, .info:
            attributes = [ ]
        }

        var log: String = ""
        
        if logLevel <= .debug {
            log.append("\(timestamp())")
            log.append(" \(level.rawValue, .bold)")
            log.append(" \(label)")
        }
        
        if Environment.shared.shouldOutputBeColoured {
            log.append(attributes.elements().reduce(message.description) { $1.apply(to: $0) })
        } else {
            log.append(message.description)
        }

        output(for: level).log(level: level, message: message, metadata: metadata, file: file, function: function, line: line)
        
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

public func zurry<A>(_ ƒ: @escaping () throws -> A) rethrows -> A {
  return try ƒ()
}

public func flip<A, B>(_ ƒ: @escaping (A) -> () -> B) -> () -> (A) -> B {
    return { { ƒ($0)() } }
}

public struct ConsoleToken: OptionSet {
    
    public static let key: String = "attributes"
    
    public let rawValue: Int
    internal let ƒ: (String) -> String
    
    public init(rawValue: Int, _ attribute: @escaping (String) -> () -> String) {
        self.rawValue = rawValue
        ƒ = zurry(flip(attribute))
    }
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
        ƒ = { $0 }
    }
    
    public static let white = ConsoleToken(rawValue: 1 << 0, String.white)
    public static let green = ConsoleToken(rawValue: 1 << 1, String.green)
    public static let red = ConsoleToken(rawValue: 1 << 2, String.red)
    public static let cyan = ConsoleToken(rawValue: 1 << 3, String.cyan)
    public static let yellow = ConsoleToken(rawValue: 1 << 4, String.yellow)

    public static let bold = ConsoleToken(rawValue: 1 << 5, String.bold)
    
    func apply(to string: String) -> String {
        ƒ(string)
    }

}

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

extension FileHandle {
    
    func print(_ string: String, terminator: String = "\n") {
        string.data(using: .utf8)
            .map(write)
        terminator.data(using: .utf8)
            .map(write)
    }
    
}

public extension OptionSet where RawValue: FixedWidthInteger {

    func elements() -> AnySequence<Self> {
        var remainingBits = rawValue
        var bitMask: RawValue = 1
        return AnySequence {
            return AnyIterator {
                while remainingBits != 0 {
                    defer { bitMask = bitMask &* 2 }
                    if remainingBits & bitMask != 0 {
                        remainingBits = remainingBits & ~bitMask
                        return Self(rawValue: bitMask)
                    }
                }
                return nil
            }
        }
    }
}
