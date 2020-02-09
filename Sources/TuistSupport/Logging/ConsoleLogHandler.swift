import Foundation
import Logging

public struct ConsoleLogHandler: LogHandler {
    
    public let label: String
    
    public static func verbose(label: String) -> LogHandler {
        ConsoleLogHandler(label: label, level: .debug)
    }
    
    public init(label: String) {
        self.label = label
    }
    
    public init(label: String, level: Logger.Level) {
        self.label = label
        self.logLevel = level
    }
    
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        file: String, function: String, line: UInt
    ) {
        
        var attributes = ConsoleToken()
        
        if case let .stringConvertible(value as ConsoleToken)? = metadata?[ConsoleToken.key] {
            attributes.formUnion(value)
        } else {
            
            let additional: ConsoleToken
            
            switch level {
            case .critical:
                additional = [ .red, .bold ]
            case .error:
                additional = [ .red ]
            case .warning:
                additional = [ .yellow ]
            case .notice:
                additional = [ .white, .bold ]
            case .debug:
                additional = [ .white ]
            case .trace:
                additional = [ .white ]
            case .info:
                additional = [ .white ]
            }
            
            attributes.formUnion(additional)
            
        }
        
        let log: String
            
        if Environment.shared.shouldOutputBeColoured {
            log = attributes.elements().reduce(message.description) { $1.apply(to: $0) }
        } else {
            log = message.description
        }
        
        if logLevel <= .debug {
            output(for: level).print("\(timestamp()) \(level.rawValue, .bold)", terminator: " ")
        }

        output(for: level).print(log)
        
    }
    
    func output(for level: Logger.Level) -> FileHandle {
        level < .error ? .standardOutput : .standardError
    }
    
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
    
    public var metadata: Logger.Metadata = .init()
    public var logLevel: Logger.Level = .info

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

extension Optional where Wrapped == Logger.Metadata {
    public static func + (lhs: Logger.Metadata?, rhs: ConsoleToken) -> Logger.Metadata {
        (lhs ?? [:]) + rhs
    }
}

extension Logger.Metadata {
    
    public static func + (lhs: Logger.Metadata, rhs: ConsoleToken) -> Logger.Metadata {
        lhs.merging([
            ConsoleToken.key: .stringConvertible(rhs)
        ], uniquingKeysWith: { $1 })
    }
    
    public init(_ attributes: ConsoleToken) {
        self = [ConsoleToken.key: .stringConvertible(attributes)]
    }
    
}

public func zurry<A>(_ ƒ: @escaping () throws -> A) rethrows -> A {
  return try ƒ()
}

public func flip<A, B>(_ ƒ: @escaping (A) -> () -> B) -> () -> (A) -> B {
    return { { ƒ($0)() } }
}

public struct ConsoleToken: OptionSet, CustomStringConvertible {
    
    public static let key: String = "attributes"
    
    public let rawValue: Int
    public let ƒ: (String) -> String
    
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
    
    public var description: String {
        var description: [String] = [ ]
        
        if contains(.white) {
            description.append("white")
        }
        
        if contains(.green) {
            description.append("green")
        }
        
        if contains(.red) {
            description.append("red")
        }
        
        if contains(.cyan) {
            description.append("cyan")
        }
        
        if contains(.yellow) {
            description.append("yellow")
        }

        if contains(.bold) {
            description.append("bold")
        }
        
        return description.joined(separator: ",")
    }
    
    func apply(to string: String) -> String {
        ƒ(string)
    }

}

extension ConsoleToken {
    public static let section: ConsoleToken = [ .cyan, .bold ]
    public static let subsection: ConsoleToken = [ .cyan ]
    public static let success: ConsoleToken = [ .green, .bold ]
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
