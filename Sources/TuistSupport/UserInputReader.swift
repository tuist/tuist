import Foundation
import Mockable

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
}

public struct UserInputReader: UserInputReading {
    private var reader: (Bool) -> String?

    public init(reader: @escaping (Bool) -> String? = readLine) {
        self.reader = reader
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
