import Darwin
import Foundation

/// Structure used to load and save environment files.
@dynamicMemberLookup
public enum Dotenv {

    // MARK: - Types

    /// Type-safe representation of the value types in a `.env` file.
    public enum Value: Equatable {
        /// Reprensents a boolean value, `true`, or `false`.
        case boolean(Bool)
        /// Represents any double literal.
        case double(Double)
        /// Represents any integer literal.
        case integer(Int)
        /// Represents any string literal.
        case string(String)

        /// Convert a value to its string representation.
        public var stringValue: String {
            switch self {
            case let .boolean(value):
                return String(describing: value)
            case let .double(value):
                return String(describing: value)
            case let .integer(value):
                return String(describing: value)
            case let .string(value):
                return value
            }
        }

        /// Create a value from a string value.
        /// - Parameter stringValue: String value.
        init?(_ stringValue: String?) {
            guard let stringValue else {
                return nil
            }
            // order of operations is important, double should get checked before integer
            // because integer's downcasting is more permissive
            if let boolValue = Bool(stringValue) {
                self = .boolean(boolValue)
            // enforcing exclusion on the double conversion
            } else if let doubleValue = Double(stringValue), Int(stringValue) == nil {
                self = .double(doubleValue)
            } else if let integerValue = Int(stringValue) {
                self = .integer(integerValue)
            } else {
                // replace escape double quotes
                self = .string(stringValue.trimmingCharacters(in: .init(charactersIn: "\"")).replacingOccurrences(of: "\\\"", with: "\""))
            }
        }

        // MARK: - Equatable

        public static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case let (.boolean(a), .boolean(b)):
                return a == b
            case let (.double(a), .double(b)):
                return a == b
            case let (.integer(a), .integer(b)):
                return a == b
            case let (.string(a), .string(b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: Errors
    
    /// Failures that can occur during loading an environment.
    public enum LoadingFailure: Error {
        /// The environment file is not at the path given.
        case environmentFileIsMissing
        /// The environment ifle is in some way malformed.
        case unableToReadEnvironmentFile
    }
    
    /// Represents errors that can occur during encoding.
    public enum DecodingFailure: Error {
        // the key value pair is in some way malformed
        case malformedKeyValuePair
        /// Either the key or value is empty.
        case emptyKeyValuePair(pair: (String, String))
    }

    // MARK: - Configuration

    /// `FileManager` instance used to load and save configuration files. Can be replaced with a custom instance.
    public static var fileManager = FileManager.default

    /// Delimeter for key value pairs, defaults to `=`.
    public static var delimeter: Character = "="

    /// Process info instance.
    public static var processInfo: ProcessInfo = ProcessInfo.processInfo

    /// Configure the environment with environment values loaded from the environment file.
    /// - Parameters:
    ///   - path: Path for the environment file, defaults to `.env`.
    ///   - overwrite: Flag that indicates if pre-existing values in the environment should be overwritten with values from the environment file, defaults to `true`.
    public static func configure(atPath path: String = ".env", overwrite: Bool = true) throws {
        let contents = try readFileContents(atPath: path)
        let lines = contents.split(separator: "\n")
        // we loop over all the entries in the file which are already separated by a newline
        for line in lines {
            // ignore comments
            if line.starts(with: "#") {
                continue
            }
            // split by the delimeter
            let substrings = line.split(separator: Self.delimeter)

            // make sure we can grab two and only two string values
            guard
                let key = substrings.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                let value = substrings.last?.trimmingCharacters(in: .whitespacesAndNewlines),
                substrings.count == 2,
                !key.isEmpty,
                !value.isEmpty else {
                    throw DecodingFailure.malformedKeyValuePair
            }
            setenv(key, value, overwrite ? 1 : 0)
        }
    }

    private static func readFileContents(atPath path: String) throws -> String {
        let fileManager = Self.fileManager
        guard fileManager.fileExists(atPath: path) else {
            throw LoadingFailure.environmentFileIsMissing
        }
        guard let contents = try? String(contentsOf: URL(fileURLWithPath: path)) else {
            throw LoadingFailure.unableToReadEnvironmentFile
        }
        return contents
    }

    // MARK: - Values

    /// All environment values.
    public static var values: [String: String] {
        processInfo.environment
    }

    // MARK: - Modification

    /// Set a value in the environment.
    /// - Parameters:
    ///   - value: Value to set.
    ///   - key: Key to set the value with.
    ///   - overwrite: Flag that indicates if any existing value should be overwritten, defaults to `true`.
    public static func set(value: Value, forKey key: String, overwrite: Bool = true) {
        set(value: value.stringValue, forKey: key, overwrite: overwrite)
    }

    /// Set a value in the environment.
    /// - Parameters:
    ///   - value: Value to set.
    ///   - key: Key to set the value with.
    ///   - overwrite: Flag that indicates if any existing value should be overwritten, defaults to `true`.
    public static func set(value: String, forKey key: String, overwrite: Bool = true) {
        setenv(key, value, overwrite ? 1 : 0)
    }

    // MARK: - Subscripting

    public static subscript(key: String) -> Value? {
        get {
            Value(values[key])
        } set {
            guard let newValue else { return }
            set(value: newValue, forKey: key)
        }
    }

    public static subscript(key: String, default defaultValue: @autoclosure () -> Value) -> Value {
        get {
            Value(values[key]) ?? defaultValue()
        } set {
            set(value: newValue, forKey: key)
        }
    }

    // MARK: Dynamic Member Lookup

    public static subscript(dynamicMember member: String) -> Value? {
        get {
            Value(values[member.camelCaseToSnakeCase().uppercased()])
        } set {
            guard let newValue else { return }
            set(value: newValue, forKey: member.camelCaseToSnakeCase().uppercased())
        }
    }
}
