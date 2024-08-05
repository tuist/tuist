import Foundation
import Mockable

enum UserInputReaderError: FatalError, Equatable {
    case noValuesProvided(String)

    var description: String {
        switch self {
        case let .noValuesProvided(prompt):
            return "No values to choose from for the prompt \(prompt)"
        }
    }

    var type: ErrorType {
        switch self {
        case .noValuesProvided:
            return .bug
        }
    }
}

@Mockable
public protocol UserInputReading {
    /// Reads an integer from the user.
    /// - Parameters:
    ///   - prompt: The prompt to be shown to the user providing context and the allowed options.
    ///   - maxValueAllowed: The max value allowed given the list of options provided in the prompt.
    func readInt(asking prompt: String, maxValueAllowed: Int) -> Int

    /// Reads a string from the user.
    /// - Parameters:
    ///     - prompt: The prompt to be shown to the user providing context and the allowed options.
    func readString(asking prompt: String) -> String

    /// Reads a value from the user.
    /// - Parameters:
    ///   - prompt: The prompt to be shown to the user providing context and the allowed options.
    ///   - values: Values to choose from.
    ///   - valueDescription: A closure for extracting description for a value. The description is used in the list of choices
    /// presented to the user in the CLI.
    func readValue<Value>(
        asking prompt: String,
        values: [Value],
        valueDescription: @escaping (Value) -> String
    ) throws -> Value
}

public struct UserInputReader: UserInputReading {
    private var reader: (Bool) -> String?

    public init(reader: @escaping (Bool) -> String? = readLine) {
        self.reader = reader
    }

    public func readValue<Value>(
        asking prompt: String,
        values: [Value],
        valueDescription: (Value) -> String
    ) throws -> Value {
        guard !values.isEmpty else { throw UserInputReaderError.noValuesProvided(prompt) }

        if values.count == 1, let onlyValue = values.first {
            return onlyValue
        } else {
            let prompt = [prompt] + values.map(valueDescription).enumerated().map { index, value in
                "\t\(index): \(value)"
            }
            let choice = readInt(asking: prompt.joined(separator: "\n"), maxValueAllowed: values.count)
            return values[choice]
        }
    }

    public func readInt(asking prompt: String, maxValueAllowed: Int) -> Int {
        while true {
            logger.notice("\(prompt)")
            if let input = reader(true), !input.isEmpty, let intValue = Int(input), intValue < maxValueAllowed {
                return intValue
            } else {
                logger.notice("Invalid input. Please enter a valid integer.")
            }
        }
    }

    public func readString(asking prompt: String) -> String {
        while true {
            logger.notice("\(prompt)")
            if let input = reader(true), !input.isEmpty {
                return input
            } else {
                logger.notice("The value is empty. Please, enter a non-empty value.")
            }
        }
    }
}
