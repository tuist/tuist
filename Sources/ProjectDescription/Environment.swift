import Foundation

/// A convenience structure to read environment variables.
@dynamicMemberLookup
public enum Environment {
    public enum Value: Equatable {
        case boolean(Bool)
        case string(String)
    }

    public static subscript(dynamicMember member: String) -> Value? {
        value(for: member, environment: ProcessInfo.processInfo.environment)
    }

    static func value(for key: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> Value? {
        let formattedName = key.camelCaseToSnakeCase().uppercased()
        guard let value = environment["TUIST_\(formattedName)"] else { return nil }
        let trueValues = ["1", "true", "TRUE", "yes", "YES"]
        let falseValues = ["0", "false", "FALSE", "no", "NO"]
        if trueValues.contains(value) {
            return .boolean(true)
        } else if falseValues.contains(value) {
            return .boolean(false)
        } else {
            return .string(value)
        }
    }
}

extension Optional where Wrapped == Environment.Value {
    /// Retrieve the Environment value as a string or return the specified default string value
    /// - Parameters:
    ///   - default: default String value to be returned
    /// - Returns: String
    public func getString(default defaultString: String) -> String {
        if case let .string(value) = self { return value }
        return defaultString
    }

    /// Retrieve the Environment value as a boolean or return the specified default boolean value
    /// - Parameters:
    ///   - default: default Boolean value to be returned
    /// - Returns: Bool
    public func getBoolean(default defaultBoolean: Bool) -> Bool {
        if case let .boolean(value) = self { return value }
        return defaultBoolean
    }
}

extension String {
    // Taken from https://github.com/apple/swift/blob/88b093e9d77d6201935a2c2fb13f27d961836777/stdlib/public/Darwin/Foundation/JSONEncoder.swift#L161
    fileprivate func camelCaseToSnakeCase() -> String {
        guard !isEmpty else { return self }

        var words: [Range<String.Index>] = []
        // The general idea of this algorithm is to split words on transition from lower to upper case, then on transition of >1 upper case characters to lowercase
        //
        // myProperty -> my_property
        // myURLProperty -> my_url_property
        //
        // We assume, per Swift naming conventions, that the first character of the key is lowercase.
        var wordStart = startIndex
        var searchRange = index(after: wordStart) ..< endIndex

        // Find next uppercase character
        while let upperCaseRange = rangeOfCharacter(from: CharacterSet.uppercaseLetters, options: [], range: searchRange) {
            let untilUpperCase = wordStart ..< upperCaseRange.lowerBound
            words.append(untilUpperCase)

            // Find next lowercase character
            searchRange = upperCaseRange.lowerBound ..< searchRange.upperBound
            guard let lowerCaseRange = rangeOfCharacter(from: CharacterSet.lowercaseLetters, options: [], range: searchRange)
            else {
                // There are no more lower case letters. Just end here.
                wordStart = searchRange.lowerBound
                break
            }

            // Is the next lowercase letter more than 1 after the uppercase? If so, we encountered a group of uppercase letters that we should treat as its own word
            let nextCharacterAfterCapital = index(after: upperCaseRange.lowerBound)
            if lowerCaseRange.lowerBound == nextCharacterAfterCapital {
                // The next character after capital is a lower case character and therefore not a word boundary.
                // Continue searching for the next upper case for the boundary.
                wordStart = upperCaseRange.lowerBound
            } else {
                // There was a range of >1 capital letters. Turn those into a word, stopping at the capital before the lower case character.
                let beforeLowerIndex = index(before: lowerCaseRange.lowerBound)
                words.append(upperCaseRange.lowerBound ..< beforeLowerIndex)

                // Next word starts at the capital before the lowercase we just found
                wordStart = beforeLowerIndex
            }
            searchRange = lowerCaseRange.upperBound ..< searchRange.upperBound
        }
        words.append(wordStart ..< searchRange.upperBound)
        let result = words.map { range in
            self[range].lowercased()
        }.joined(separator: "_")
        return result
    }
}
